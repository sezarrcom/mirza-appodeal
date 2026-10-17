/// Appodeal mediation for the Mirza Games apps (17 Oct 2026), shared so every
/// game runs the same adapter and consent flow; first written for Arrowtide.
/// A game wires it with
///
///   pluginAds: PluginAds(
///     create: () => AppodealAdapter(appKey: key),
///     consent: () => AppodealConsent(appKey: key),
///   ),
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mirza_core/mirza_core.dart';
import 'package:stack_appodeal_flutter/stack_appodeal_flutter.dart';

/// The calls the adapter makes on the Appodeal plugin. The real one
/// ([AppodealPluginApi]) forwards each; tests pass a fake.
abstract class AppodealApi {
  Future<void> init({required String appKey, required bool testMode, required void Function(bool ok) onDone});
  void setRewardedCallbacks({
    required void Function() onLoaded,
    required void Function() onLoadFailed,
    required void Function() onShowFailed,
    required void Function() onFinished,
    required void Function(bool finished) onClosed,
    required void Function() onExpired,
  });
  void setInterstitialCallbacks({
    required void Function() onLoaded,
    required void Function() onLoadFailed,
    required void Function() onShowFailed,
    required void Function() onClosed,
    required void Function() onExpired,
  });
  void cache({required bool rewarded});
  Future<bool> show({required bool rewarded, required String placement});
}

/// The real thing: Appodeal SDK 4.3 through `stack_appodeal_flutter` 4.3.1.
class AppodealPluginApi implements AppodealApi {
  const AppodealPluginApi();

  static AppodealAdType _type(bool rewarded) => rewarded ? AppodealAdType.RewardedVideo : AppodealAdType.Interstitial;

  @override
  Future<void> init({required String appKey, required bool testMode, required void Function(bool ok) onDone}) async {
    Appodeal.setTesting(testMode);
    // AdsMax asks for each ad itself (load, then show), as on every network.
    Appodeal.setAutoCache(AppodealAdType.Interstitial, false);
    Appodeal.setAutoCache(AppodealAdType.RewardedVideo, false);
    Appodeal.setChildDirectedTreatment(false);
    Appodeal.initialize(
      appKey: appKey,
      adTypes: const [AppodealAdType.Interstitial, AppodealAdType.RewardedVideo],
      onInitializationFinished: (errors) {
        // Errors here are per network (one adapter missing a setting); the
        // SDK still serves the others.
        if (errors != null && errors.isNotEmpty) debugPrint('Appodeal: init notes: ${errors.map((e) => e.description)}');
        onDone(true);
      },
    );
  }

  @override
  void setRewardedCallbacks({
    required void Function() onLoaded,
    required void Function() onLoadFailed,
    required void Function() onShowFailed,
    required void Function() onFinished,
    required void Function(bool finished) onClosed,
    required void Function() onExpired,
  }) =>
      Appodeal.setRewardedVideoCallbacks(
        onRewardedVideoLoaded: (_) => onLoaded(),
        onRewardedVideoFailedToLoad: onLoadFailed,
        onRewardedVideoShowFailed: onShowFailed,
        onRewardedVideoFinished: (_, _) => onFinished(),
        onRewardedVideoClosed: onClosed,
        onRewardedVideoExpired: onExpired,
      );

  @override
  void setInterstitialCallbacks({
    required void Function() onLoaded,
    required void Function() onLoadFailed,
    required void Function() onShowFailed,
    required void Function() onClosed,
    required void Function() onExpired,
  }) =>
      Appodeal.setInterstitialCallbacks(
        onInterstitialLoaded: (_) => onLoaded(),
        onInterstitialFailedToLoad: onLoadFailed,
        onInterstitialShowFailed: onShowFailed,
        onInterstitialClosed: onClosed,
        onInterstitialExpired: onExpired,
      );

  @override
  void cache({required bool rewarded}) => Appodeal.cache(_type(rewarded));

  @override
  Future<bool> show({required bool rewarded, required String placement}) => Appodeal.show(_type(rewarded), placement);
}

/// Appodeal (mediation over Unity Ads, AppLovin, Mintegral, Vungle and the
/// other networks its dashboard connects) as the network under AdsMax. Like
/// the Unity adapter it only translates; the rules stay in AdsMax.
///
/// - A rewarded view pays once, when Appodeal says it was finished (the
///   finish event, or a close that reports a finished view).
/// - An expired cached ad counts as not loaded, so AdsMax asks again.
/// - Test mode follows [UnityAdsMode]: on in debug, profile and demo builds.
class AppodealAdapter implements MaxAdPlugin {
  AppodealAdapter({
    AppodealApi? api,
    required this.appKey,
    bool Function()? testMode,
    this.initTimeout = const Duration(seconds: 20),
  })  : _api = api ?? const AppodealPluginApi(),
        _testMode = testMode ?? UnityAdsMode.testMode;

  final AppodealApi _api;
  final String appKey;
  final bool Function() _testMode;
  final Duration initTimeout;

  MaxAdCallbacks? _rewarded;
  MaxAdCallbacks? _interstitial;
  bool _initialized = false;
  Future<bool>? _starting;

  // One rewarded show at a time: whether it has paid and whether it ended.
  bool _paid = false;
  bool _rewardedOpen = false;
  bool _interstitialOpen = false;

  @override
  Future<bool> start() {
    if (_initialized) return Future.value(true);
    return _starting ??= _startOnce().whenComplete(() => _starting = null);
  }

  Future<bool> _startOnce() async {
    if (appKey.trim().isEmpty) return false;
    final done = Completer<bool>();
    _wireCallbacks();
    try {
      await _api.init(
        appKey: appKey,
        testMode: _testMode(),
        onDone: (ok) {
          _initialized = ok;
          if (!done.isCompleted) done.complete(ok);
        },
      );
    } catch (e) {
      debugPrint('Appodeal: init failed: $e');
      if (!done.isCompleted) done.complete(false);
    }
    return done.future.timeout(initTimeout, onTimeout: () => _initialized);
  }

  void _wireCallbacks() {
    _api.setRewardedCallbacks(
      onLoaded: () => _rewarded?.onLoaded(),
      onLoadFailed: () => _rewarded?.onLoadFailed(),
      onExpired: () => _rewarded?.onLoadFailed(),
      onShowFailed: () {
        if (!_rewardedOpen) return;
        _rewardedOpen = false;
        _rewarded?.onDisplayFailed();
      },
      onFinished: _pay,
      onClosed: (finished) {
        if (!_rewardedOpen) return;
        if (finished) _pay();
        _rewardedOpen = false;
        _rewarded?.onHidden();
      },
    );
    _api.setInterstitialCallbacks(
      onLoaded: () => _interstitial?.onLoaded(),
      onLoadFailed: () => _interstitial?.onLoadFailed(),
      onExpired: () => _interstitial?.onLoadFailed(),
      onShowFailed: () {
        if (!_interstitialOpen) return;
        _interstitialOpen = false;
        _interstitial?.onDisplayFailed();
      },
      onClosed: () {
        if (!_interstitialOpen) return;
        _interstitialOpen = false;
        _interstitial?.onHidden();
      },
    );
  }

  void _pay() {
    if (!_rewardedOpen || _paid) return;
    _paid = true;
    _rewarded?.onReward?.call();
  }

  @override
  void setRewardedCallbacks(MaxAdCallbacks callbacks) => _rewarded = callbacks;

  @override
  void setInterstitialCallbacks(MaxAdCallbacks callbacks) => _interstitial = callbacks;

  @override
  void loadRewarded(String adUnitId) => _load(rewarded: true);

  @override
  void loadInterstitial(String adUnitId) => _load(rewarded: false);

  void _load({required bool rewarded}) {
    try {
      _api.cache(rewarded: rewarded);
    } catch (e) {
      debugPrint('Appodeal: cache failed: $e');
      (rewarded ? _rewarded : _interstitial)?.onLoadFailed();
    }
  }

  @override
  void showRewarded(String adUnitId) {
    _paid = false;
    _rewardedOpen = true;
    _show(rewarded: true, placement: adUnitId);
  }

  @override
  void showInterstitial(String adUnitId) {
    _interstitialOpen = true;
    _show(rewarded: false, placement: adUnitId);
  }

  void _show({required bool rewarded, required String placement}) {
    void failed(Object e) {
      debugPrint('Appodeal: show failed: $e');
      if (rewarded ? !_rewardedOpen : !_interstitialOpen) return;
      if (rewarded) {
        _rewardedOpen = false;
      } else {
        _interstitialOpen = false;
      }
      (rewarded ? _rewarded : _interstitial)?.onDisplayFailed();
    }

    try {
      unawaited(_api.show(rewarded: rewarded, placement: placement).then((shown) {
        if (!shown) failed('not shown');
      }).catchError(failed));
    } catch (e) {
      failed(e);
    }
  }
}

/// Appodeal's consent flow (Stack Consent Manager, on Google UMP, IAB TCF v2)
/// for Consent: the form where the law asks for one (EEA, UK, Switzerland),
/// before any ad loads, and the privacy form behind Settings -> Privacy
/// options for players in regulated US states (opt-out) and in the EEA
/// (re-consent).
class AppodealConsent implements PluginConsent {
  AppodealConsent({required this.appKey, this.answerWait = const Duration(seconds: 90)});

  final String appKey;

  /// How long ads wait for an answer. The form stays up after that; the
  /// SDK reads the answer on its own when it comes.
  final Duration answerWait;

  bool _optionsRequired = false;

  @override
  bool get privacyOptionsRequired => _optionsRequired;

  @override
  Future<bool> gather() async {
    final done = Completer<void>();
    try {
      Appodeal.ConsentForm.loadAndShowIfRequired(
        appKey: appKey,
        onConsentFormDismissed: (error) {
          if (error != null) debugPrint('Appodeal consent: ${error.description}');
          if (!done.isCompleted) done.complete();
        },
      );
      await done.future.timeout(answerWait, onTimeout: () {});
      _optionsRequired =
          await Appodeal.ConsentForm.getPrivacyOptionsRequirementStatus() == PrivacyOptionsRequirementStatus.required;
    } catch (e) {
      debugPrint('Appodeal consent: $e');
    }
    // The SDK applies the answer to every request itself: a refusal only
    // means non-personalised ads, so ads may always be requested.
    return true;
  }

  @override
  Future<void> showPrivacyOptions() async {
    final done = Completer<void>();
    try {
      Appodeal.ConsentForm.showPrivacyOptionsForm(onConsentFormDismissed: (_) {
        if (!done.isCompleted) done.complete();
      });
      await done.future.timeout(const Duration(minutes: 5), onTimeout: () {});
    } catch (e) {
      debugPrint('Appodeal privacy options: $e');
    }
  }
}

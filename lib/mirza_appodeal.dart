/// Appodeal mediation for the Mirza Games apps (17 Oct 2026), shared so every
/// game runs the same adapter and consent flow; first written for Arrowtide.
/// A game wires it with
///
///   pluginAds: PluginAds(
///     create: () => AppodealAdapter(appKey: key),
///     consent: () => AppodealConsent(appKey: key),
///     banner: 'default', // the bottom banner (BannerSlot); empty for none
///   ),
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:mirza_core/mirza_core.dart';
import 'package:stack_appodeal_flutter/stack_appodeal_flutter.dart';

/// The calls the adapter makes on the Appodeal plugin. The real one
/// ([AppodealPluginApi]) forwards each; tests pass a fake.
abstract class AppodealApi {
  /// [banners] brings the banner format up too (auto-cached by the SDK).
  Future<void> init({
    required String appKey,
    required bool testMode,
    required bool banners,
    required void Function(bool ok) onDone,
  });
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

  /// The banner's events: an ad is in the view (loaded or shown), or none
  /// could be loaded or shown.
  void setBannerCallbacks({required void Function() onLoaded, required void Function() onFailed});

  /// The SDK's single 320 x 50 banner view for [placement], as a widget
  /// that takes layout space (never the SDK's overlay banner).
  Widget bannerView(String placement);
}

/// The real thing: Appodeal SDK 4.3 through `stack_appodeal_flutter` 4.3.1.
class AppodealPluginApi implements AppodealApi {
  const AppodealPluginApi();

  static AppodealAdType _type(bool rewarded) => rewarded ? AppodealAdType.RewardedVideo : AppodealAdType.Interstitial;

  @override
  Future<void> init({
    required String appKey,
    required bool testMode,
    required bool banners,
    required void Function(bool ok) onDone,
  }) async {
    Appodeal.setTesting(testMode);
    // AdsMax asks for each ad itself (load, then show), as on every network.
    Appodeal.setAutoCache(AppodealAdType.Interstitial, false);
    Appodeal.setAutoCache(AppodealAdType.RewardedVideo, false);
    // The banner refreshes on its own: the SDK caches the next one.
    if (banners) Appodeal.setAutoCache(AppodealAdType.Banner, true);
    Appodeal.setChildDirectedTreatment(false);
    Appodeal.initialize(
      appKey: appKey,
      adTypes: [
        AppodealAdType.Interstitial,
        AppodealAdType.RewardedVideo,
        if (banners) AppodealAdType.Banner,
      ],
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

  @override
  void setBannerCallbacks({required void Function() onLoaded, required void Function() onFailed}) =>
      Appodeal.setBannerCallbacks(
        onBannerLoaded: (_) => onLoaded(),
        onBannerShown: onLoaded,
        onBannerFailedToLoad: onFailed,
        onBannerShowFailed: onFailed,
      );

  @override
  Widget bannerView(String placement) => AppodealBanner(adSize: AppodealBannerSize.BANNER, placement: placement);
}

/// Appodeal (mediation over Unity Ads, AppLovin, Mintegral, Vungle and the
/// other networks its dashboard connects) as the network under AdsMax. Like
/// the Unity adapter it only translates; the rules stay in AdsMax.
///
/// - A rewarded view pays once, when Appodeal says it was finished (the
///   finish event, or a close that reports a finished view).
/// - An expired cached ad counts as not loaded, so AdsMax asks again.
/// - Test mode follows [UnityAdsMode]: on in debug, profile and demo builds.
class AppodealAdapter implements MaxAdPlugin, BannerAdPlugin {
  AppodealAdapter({
    AppodealApi? api,
    required this.appKey,
    bool Function()? testMode,
    bool Function()? banners,
    this.initTimeout = const Duration(seconds: 20),
  })  : _api = api ?? const AppodealPluginApi(),
        _testMode = testMode ?? UnityAdsMode.testMode,
        _banners = banners ?? (() => BannerAds.wantedAtStart);

  final AppodealApi _api;
  final String appKey;
  final bool Function() _testMode;

  /// Whether the banner format is brought up at start
  /// ([BannerAds.wantedAtStart]: a placement, no Remove Ads, a surface
  /// switched on). A Remove Ads buyer's session never asks for a banner.
  final bool Function() _banners;
  final Duration initTimeout;

  /// The banner format was brought up.
  bool _bannersOn = false;

  /// What the SDK last said about its banner: null before anything, true
  /// when an ad is in the view, false when none came.
  bool? _bannerLoaded;
  final Set<_BannerListener> _bannerListeners = {};

  /// Whether the banner format is up (tests).
  @visibleForTesting
  bool get bannersOn => _bannersOn;

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
    try {
      _bannersOn = _banners();
    } catch (e) {
      _bannersOn = false;
    }
    _wireCallbacks();
    try {
      await _api.init(
        appKey: appKey,
        testMode: _testMode(),
        banners: _bannersOn,
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
    if (_bannersOn) {
      _api.setBannerCallbacks(
        onLoaded: () => _bannerEvent(true),
        onFailed: () => _bannerEvent(false),
      );
    }
  }

  void _bannerEvent(bool loaded) {
    _bannerLoaded = loaded;
    for (final l in List.of(_bannerListeners)) {
      loaded ? l.onLoaded() : l.onFailed();
    }
  }

  @override
  Size bannerSize(double maxWidth) => const Size(320, 50);

  @override
  Widget buildBanner({
    required String placement,
    required Size size,
    required void Function() onLoaded,
    required void Function() onFailed,
  }) {
    if (!_initialized || !_bannersOn || placement.isEmpty) return const SizedBox.shrink();
    return _AppodealBannerView(adapter: this, placement: placement, onLoaded: onLoaded, onFailed: onFailed);
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

class _BannerListener {
  final void Function() onLoaded;
  final void Function() onFailed;
  _BannerListener(this.onLoaded, this.onFailed);
}

/// One slot's banner: the SDK's view, and its events. Appodeal has a single
/// banner view and reports its events for the whole app; a view built while
/// an ad is already in it reports it at once.
class _AppodealBannerView extends StatefulWidget {
  final AppodealAdapter adapter;
  final String placement;
  final void Function() onLoaded;
  final void Function() onFailed;
  const _AppodealBannerView({
    required this.adapter,
    required this.placement,
    required this.onLoaded,
    required this.onFailed,
  });

  @override
  State<_AppodealBannerView> createState() => _AppodealBannerViewState();
}

class _AppodealBannerViewState extends State<_AppodealBannerView> {
  late final _BannerListener _listener = _BannerListener(() => widget.onLoaded(), () => widget.onFailed());

  @override
  void initState() {
    super.initState();
    widget.adapter._bannerListeners.add(_listener);
    if (widget.adapter._bannerLoaded == true) widget.onLoaded();
  }

  @override
  void dispose() {
    widget.adapter._bannerListeners.remove(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.adapter._api.bannerView(widget.placement);
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

// Appodeal's revenue report becomes Firebase's ad_impression (19 Oct 2026):
// the adapter registers for the SDK's revenue callback at start and logs each
// report through the shared facade with the GA4 ad-revenue fields.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirza_appodeal/mirza_appodeal.dart';
import 'package:mirza_core/mirza_core.dart';
import 'package:stack_appodeal_flutter/stack_appodeal_flutter.dart';

class _FakeApi implements AppodealApi {
  void Function(AppodealRevenue)? onRevenue;

  @override
  Future<void> init({
    required String appKey,
    required bool testMode,
    required bool banners,
    required void Function(bool ok) onDone,
  }) async =>
      onDone(true);

  @override
  void setRevenueCallback(void Function(AppodealRevenue revenue) onRevenue) => this.onRevenue = onRevenue;

  @override
  void setRewardedCallbacks({
    required void Function() onLoaded,
    required void Function() onLoadFailed,
    required void Function() onShowFailed,
    required void Function() onFinished,
    required void Function(bool finished) onClosed,
    required void Function() onExpired,
  }) {}

  @override
  void setInterstitialCallbacks({
    required void Function() onLoaded,
    required void Function() onLoadFailed,
    required void Function() onShowFailed,
    required void Function() onClosed,
    required void Function() onExpired,
  }) {}

  @override
  void setBannerCallbacks({required void Function() onLoaded, required void Function() onFailed}) {}

  @override
  void cache({required bool rewarded}) {}

  @override
  Future<bool> show({required bool rewarded, required String placement}) async => true;

  @override
  Widget bannerView(String placement) => const SizedBox.shrink();
}

/// A fake that predates the revenue seam: the default is a no-op, so it
/// still compiles and starts.
class _OldFakeApi extends _FakeApi {
  @override
  void setRevenueCallback(void Function(AppodealRevenue revenue) onRevenue) => super.setRevenueCallback((_) {});
}

void main() {
  final events = <(String, Map<String, Object?>)>[];
  setUp(() {
    events.clear();
    Analytics.instance.sink = (n, p) => events.add((n, p));
  });
  tearDown(() => Analytics.instance.sink = null);

  const report = AppodealRevenue(
    format: 'banner',
    networkName: 'Unity Ads',
    demandSource: 'Unity',
    adUnitName: 'banner_320x50',
    placement: 'default',
    revenue: 0.0031,
    currency: 'USD',
    precision: 'exact',
  );

  test('the adapter registers for revenue at start and logs each report as ad_impression', () async {
    final api = _FakeApi();
    final ads = AppodealAdapter(api: api, appKey: 'k', testMode: () => true, banners: () => false);
    expect(await ads.start(), isTrue);
    expect(api.onRevenue, isNotNull, reason: 'wired before the SDK initialises, so a banner paid at once is counted');
    api.onRevenue!(report);
    expect(events.map((e) => e.$1), ['ad_impression']);
    expect(events.single.$2, {
      'ad_unit': 'banner_320x50',
      'demand_source': 'Unity',
      'precision': 'exact',
      'ad_platform': 'appodeal',
      'ad_format': 'banner',
      'ad_source': 'Unity Ads',
      'ad_unit_name': 'default',
      'value': 0.0031,
      'currency': 'USD',
    });
    expect(events.single.$2['value'], isA<double>());
  });

  test('a fake without the seam still starts (the method has a default)', () async {
    final ads = AppodealAdapter(api: _OldFakeApi(), appKey: 'k', testMode: () => true, banners: () => false);
    expect(await ads.start(), isTrue);
  });

  test("the SDK's ad types are named the way GA4's ad_format wants them", () {
    for (final t in [
      AppodealAdType.Banner,
      AppodealAdType.BannerBottom,
      AppodealAdType.BannerTop,
      AppodealAdType.BannerLeft,
      AppodealAdType.BannerRight
    ]) {
      expect(appodealFormatName(t), 'banner');
    }
    expect(appodealFormatName(AppodealAdType.Interstitial), 'interstitial');
    expect(appodealFormatName(AppodealAdType.RewardedVideo), 'rewarded');
    expect(appodealFormatName(AppodealAdType.MREC), 'mrec');
    expect(appodealFormatName(AppodealAdType.NativeAd), 'native');
    expect(appodealFormatName(AppodealAdType.None), 'unknown');
    expect(appodealFormatName(AppodealAdType.All), 'unknown');
  });

  test('fromSdk carries every field over and names the format', () {
    // The SDK's own object is built from the platform channel's map; the
    // type code is the host platform's (iOS codes off Android).
    final sdk = AppodealAdRevenue.fromArgs({
      'adType': AppodealAdType.Interstitial.platformType,
      'networkName': 'AppLovin',
      'demandSource': 'AppLovin Exchange',
      'adUnitName': 'inter',
      'placement': 'default',
      'revenue': 0.0125,
      'currency': 'USD',
      'revenuePrecision': 'estimated',
    });
    final r = AppodealRevenue.fromSdk(sdk);
    expect(r.format, 'interstitial');
    expect(r.networkName, 'AppLovin');
    expect(r.demandSource, 'AppLovin Exchange');
    expect(r.adUnitName, 'inter');
    expect(r.placement, 'default');
    expect(r.revenue, 0.0125);
    expect(r.currency, 'USD');
    expect(r.precision, 'estimated');
  });
}

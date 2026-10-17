# mirza_appodeal

Appodeal mediation (SDK 4.3.0) for the Mirza Games apps, plugged into mirza_core's AdsMax as an app's own network (`PluginAds`).

**Per app:**
1. `pubspec.yaml`: `mirza_appodeal: path: ../packages/mirza_appodeal` (adjust the depth).
2. Config: `pluginAds: PluginAds(create: () => AppodealAdapter(appKey: k), consent: () => AppodealConsent(appKey: k))`. The key comes from app.appodeal.com; it is not a secret.
   Bottom banner (17 Oct 2026): add `banner: 'default'` to `PluginAds` and put `BannerSlot(surface: BannerSurface.home | .game)` (mirza_core) as the last child of each screen's layout column. The adapter then initialises Appodeal with the Banner type (unless Remove Ads was bought or both Remote Config switches `banner_home`/`banner_game` are off) and serves the SDK's 320x50 view, which takes layout space and is never the overlay banner.
3. `android/build.gradle.kts` allprojects repositories: `maven { url = uri("https://artifactory.appodeal.com/appodeal") }`.
4. `android/app/build.gradle.kts` dependencies: the adapter list from arrowtide/android/app/build.gradle.kts (no AdMob).
5. `android/app/proguard-rules.pro`: `-dontwarn com.facebook.infer.annotation.**`.
6. The privacy page names Appodeal; app-ads.txt already carries Appodeal's sellers.
7. Test from a Play install only. A `.demo` package gets SdkConfigurationError, because Appodeal checks the package.

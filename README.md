# mirza_appodeal

Appodeal mediation (SDK 4.3.0) for the Mirza Games apps, plugged into mirza_core's AdsMax as an app's own network (`PluginAds`).

**Per app:**
1. `pubspec.yaml`: `mirza_appodeal: path: ../packages/mirza_appodeal` (adjust the depth).
2. Config: `pluginAds: PluginAds(create: () => AppodealAdapter(appKey: k), consent: () => AppodealConsent(appKey: k))`. The key comes from app.appodeal.com; it is not a secret.
3. `android/build.gradle.kts` allprojects repositories: `maven { url = uri("https://artifactory.appodeal.com/appodeal") }`.
4. `android/app/build.gradle.kts` dependencies: the adapter list from arrowtide/android/app/build.gradle.kts (no AdMob).
5. `android/app/proguard-rules.pro`: `-dontwarn com.facebook.infer.annotation.**`.
6. The privacy page names Appodeal; app-ads.txt already carries Appodeal's sellers.
7. Test from a Play install only. A `.demo` package gets SdkConfigurationError, because Appodeal checks the package.

"""Switch one game to Appodeal (17 Oct 2026).

  python apply_to_game.py <repo dir> <config dart file> <dart prefix> <app key>

e.g. python apply_to_game.py D:/Project/App/blockflow lib/blocktide_core.dart blocktide 36f3...

Edits, idempotent:
  pubspec.yaml               mirza_appodeal path dependency
  <config>                   import, the key, pluginAds in the builder and the live config
  android/build.gradle.kts   the Appodeal artifactory repo
  android/app/build.gradle.kts  the network adapters (Arrowtide's list)
  android/app/proguard-rules.pro  -dontwarn com.facebook.infer.annotation.**
"""
import os
import re
import sys

repo, cfg_rel, prefix, key = sys.argv[1:5]
HERE = os.path.dirname(os.path.abspath(__file__))


def rw(path, fn):
    p = os.path.join(repo, path)
    s = open(p, encoding='utf-8').read()
    t = fn(s)
    if t != s:
        open(p, 'w', encoding='utf-8', newline='\n').write(t)
        print('edited', path)


def pubspec(s):
    if 'mirza_appodeal:' in s:
        return s
    rel = os.path.relpath(HERE, repo).replace('\\', '/')
    m = re.search(r'(  mirza_core:\n    path: [^\n]+\n)', s)
    assert m, 'mirza_core dependency not found'
    return s[:m.end()] + f'  # Appodeal mediation (17 Oct 2026); adapters in android/app/build.gradle.kts.\n  mirza_appodeal:\n    path: {rel}\n' + s[m.end():]


def config(s):
    if 'AppodealAdapter' in s:
        return s
    s = s.replace("import 'package:mirza_core/mirza_core.dart';",
                  "import 'package:mirza_appodeal/mirza_appodeal.dart';\nimport 'package:mirza_core/mirza_core.dart';", 1)
    # the live config line: final <x>Config = <builder>(unityAds: <const>);
    m = re.search(r'final (\w+Config) = (\w+)\(unityAds: (\w+)\);', s)
    assert m, 'live config line not found'
    name, builder, unity = m.groups()
    live = (f"/// The App Key of this game's Appodeal app (app.appodeal.com); not a secret.\n"
            f"const {prefix}AppodealKey = '{key}';\n\n"
            f"/// Ads through Appodeal mediation (owner's decision, 17 Oct 2026), which\n"
            f"/// brings Unity Ads with the other networks; [{unity}] stays for a quick\n"
            f"/// way back. packages/mirza_appodeal.\n"
            f"final {name} = {builder}(\n"
            f"  unityAds: {unity},\n"
            f"  pluginAds: PluginAds(\n"
            f"    create: () => AppodealAdapter(appKey: {prefix}AppodealKey),\n"
            f"    consent: () => AppodealConsent(appKey: {prefix}AppodealKey),\n"
            f"    // the bottom banner (BannerSlot): Appodeal's default placement\n"
            f"    banner: 'default',\n"
            f"  ),\n"
            f");")
    s = s[:m.start()] + live + s[m.end():]
    s = re.sub(r'(\n\s*UnityAdIds unityAds = UnityAdIds\.none,\n)', r'\1  PluginAds? pluginAds,\n', s, count=1)
    s = re.sub(r'(\n(\s*)unityAds: unityAds,\n)', lambda mm: mm.group(1) + mm.group(2) + 'pluginAds: pluginAds,\n', s, count=1)
    assert 'PluginAds? pluginAds' in s and 'pluginAds: pluginAds,' in s, 'builder not patched'
    return s


def root_gradle(s):
    if 'artifactory.appodeal.com' in s:
        return s
    return re.sub(r'(allprojects \{\n    repositories \{\n        google\(\)\n        mavenCentral\(\)\n)',
                  r'\1        // Appodeal SDK and its network adapters.\n        maven { url = uri("https://artifactory.appodeal.com/appodeal") }\n', s, count=1)


ADAPTERS = None


def app_gradle(s):
    if 'com.appodeal.ads.sdk:core' in s:
        return s
    src = open(os.path.join(HERE, '..', '..', 'arrowtide', 'android', 'app', 'build.gradle.kts'), encoding='utf-8').read()
    lines = [l for l in src.splitlines() if 'com.appodeal.ads.sdk' in l]
    block = '\n    // Appodeal (17 Oct 2026): the networks it mediates; the dashboard\n    // connects them. No AdMob adapter (no AdMob account). packages/mirza_appodeal.\n' + '\n'.join(lines) + '\n'
    i = s.rindex('dependencies {')
    j = s.index('\n}', i)
    return s[:j] + '\n' + block + s[j:]


def proguard(s):
    if 'com.facebook.infer.annotation' in s:
        return s
    return s.rstrip('\n') + '\n\n# Appodeal (17 Oct 2026): the Meta Audience Network adapter references\n# Facebook\'s Infer nullness annotations, which are not shipped.\n-dontwarn com.facebook.infer.annotation.**\n'


rw('pubspec.yaml', pubspec)
rw(cfg_rel, config)
rw('android/build.gradle.kts', root_gradle)
rw('android/app/build.gradle.kts', app_gradle)
rw('android/app/proguard-rules.pro', proguard)
for f in ['android/build.gradle.kts']:
    assert 'artifactory.appodeal.com' in open(os.path.join(repo, f), encoding='utf-8').read(), f + ': repo not added'
print('done', repo)

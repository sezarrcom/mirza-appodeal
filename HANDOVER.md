# mirza_appodeal: handover (30 Oct 2026)

Appodeal ads package, used by Deal Circle Spades and Callbreak.

| | |
|---|---|
| Version | `0.1.0` |
| Repo / branch | https://github.com/sezarrcom/mirza-appodeal.git / `master` |

Needs next to it: `../../blockflow/packages/mirza_core`

## Notes

- `apply_to_game.py` wires a game to Appodeal (bottom banner uses Appodeal's default placement).

Used by the apps through `path:` dependencies, so the folder layout D:/Project/App/... must stay the same on every machine.
Studio handover: sezarrcom/Mirza-Studio-Handover.

## Recent commits

- 2026-10-30 `721af94` apply_to_game: the bottom banner uses Appodeal's default placement
- 2026-10-19 `0fcba5f` mirza_appodeal: Appodeal's revenue callback becomes ad_impression (ad_platform appodeal, ad_format, ad_source, ad_unit_name, value, currency) through the shared facade, so GA4 reads ad revenue by stream
- 2026-10-17 `fa99cb4` Bottom banner: Appodeal Banner type at init (unless Remove Ads or both switches off), banner events and the SDK's 320x50 view as a BannerAdPlugin for mirza_core's BannerSlot
- 2026-10-17 `3abd1a9` mirza_appodeal: shared Appodeal adapter and consent flow for the Mirza Games apps (from Arrowtide), with apply_to_game.py

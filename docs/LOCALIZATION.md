# Dev Island Localization Contract

Dev Island currently ships two reviewed interface languages:

- English (`en`), the development and fallback language
- Simplified Chinese (`zh-Hans`)

The default `system` preference maps Simplified Chinese system locales to
`zh-Hans` and falls back to English for every language that is not yet shipped.
Traditional Chinese deliberately remains on the English fallback until a
separate reviewed `zh-Hant` catalog exists.

## Runtime behavior

`LocalizedAppRoot` is the localization boundary for every AppKit-hosted SwiftUI
root. It reads `devIsland.interfaceLanguage` and injects both the selected
`DevIslandLanguage` and its `Locale` into the environment. Changing the value in
Settings refreshes all open Dev Island windows; the app never writes the global
`AppleLanguages` preference and does not require a relaunch.

All product copy uses `L10n`, including literal SwiftUI controls, formatted
counts, model labels, accessibility summaries, AppKit menus and system
notification titles. This is intentional: an app-level language override does
not make bare SwiftUI literals resolve consistently in every AppKit and SwiftPM
host. The only reviewed direct literals are product/provider names, the app
version label and technical input hints. Missing keys return the English source
key instead of an empty label or a crash.

Agent-authored task titles, commands, paths, provider messages and user content
are not translated. This preserves technical meaning and avoids presenting a
translation as the provider's original output.

## Source and packaging

The catalogs live in:

- `IslandAppLib/Resources/en.lproj/Localizable.strings`
- `IslandAppLib/Resources/zh-Hans.lproj/Localizable.strings`

SwiftPM processes them for unit and snapshot tests. `scripts/build-app.sh`
copies the same source catalogs into `Dev Island.app/Contents/Resources`, so the
packaged product and tests cannot drift onto separate translations.

`scripts/ci/verify-localizations.sh` rejects malformed catalogs, mismatched key
sets, literal `L10n` calls without catalog entries, unreviewed bare SwiftUI
product copy, missing SwiftPM resources, missing app-bundle packaging, or
deleted localization regression tests. CI also verifies both catalogs inside
the final Universal app.

## Adding or changing copy

1. Add the same key to both catalogs and keep format placeholders compatible.
2. Use `L10n` for both dynamic values and literal controls. Keep Agent-authored
   titles, commands, paths, prompts, responses and answer choices verbatim.
3. Add a focused test for language resolution, fallback or formatting behavior
   when the change adds a new contract.
4. Render English and Simplified Chinese snapshots for every affected fixed-size
   surface and inspect wrapping, contrast, truncation and control width.
5. Build the Universal app and verify that every supported `.lproj` is present
   in `Contents/Resources` before a release artifact is accepted.

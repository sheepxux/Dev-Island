#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail() {
  echo "::error::$1" >&2
  exit 1
}

ENGLISH="IslandAppLib/Resources/en.lproj/Localizable.strings"
SIMPLIFIED_CHINESE="IslandAppLib/Resources/zh-Hans.lproj/Localizable.strings"
PACKAGE="Package.swift"
BUILDER="scripts/build-app.sh"
HISTORY_PRESENTATION="IslandAppLib/Presentation/TaskHistoryPresentation.swift"
HISTORY_VIEW="IslandAppLib/Views/History/TaskHistoryView.swift"
STATUS_PRESENTATION="IslandAppLib/StatusBar/StatusMenuPresentation.swift"
STATUS_ITEM="IslandAppLib/StatusBar/StatusItemController.swift"
NOTIFIER="IslandAppLib/Notifications/TaskNotifier.swift"
ACTION_PRESENTATION="IslandAppLib/Presentation/ActionRequestPresentationPolicy.swift"
ACTION_SURFACE="IslandAppLib/Views/NotchPanel/ActionRequestSurface.swift"

for catalog in "$ENGLISH" "$SIMPLIFIED_CHINESE"; do
  test -s "$catalog" || fail "Localization catalog is missing or empty: $catalog"
  plutil -lint "$catalog" >/dev/null \
    || fail "Localization catalog is not a valid strings property list: $catalog"
done

catalog_keys() {
  plutil -convert xml1 -o - "$1" \
    | sed -n 's|.*<key>\(.*\)</key>.*|\1|p' \
    | sed 's|&amp;|\&|g' \
    | LC_ALL=C sort
}

if ! diff -u \
  <(catalog_keys "$ENGLISH") \
  <(catalog_keys "$SIMPLIFIED_CHINESE") >/dev/null; then
  fail "English and Simplified Chinese catalogs must contain exactly the same keys"
fi

literal_l10n_keys() {
  rg -l 'L10n\.(string|format)' IslandAppLib IslandApp --glob '*.swift' \
    | xargs perl -0ne '
        while (/L10n\.(?:string|format)\(\s*"((?:\\.|[^"])*)"/sg) {
          print "$1\n";
        }
      ' \
    | LC_ALL=C sort -u
}

MISSING_LITERAL_KEYS="$(comm -23 \
  <(literal_l10n_keys) \
  <(catalog_keys "$ENGLISH"))"
if [[ -n "$MISSING_LITERAL_KEYS" ]]; then
  echo "$MISSING_LITERAL_KEYS" >&2
  fail "Every literal L10n key used by app source must exist in the catalogs"
fi

# App-language overrides do not reliably localize a bare SwiftUI string in
# every host (notably SwiftPM tests and AppKit-hosted roots). Product copy must
# therefore use L10n explicitly. Brand names, a version label, the API-key
# format hint and groupLabel's already-localized input are the only reviewed
# direct literals.
BARE_UI_COPY="$(
  rg -n \
    '(Text|Button|Label|TextField|Picker|Toggle|SecureField|accessibilityLabel|accessibilityHint|accessibilityValue|help|alert)\(\s*"[A-Za-z]' \
    IslandAppLib/Views \
    IslandAppLib/Support \
    IslandAppLib/Updates \
    IslandAppLib/Usage \
    IslandAppLib/Windows \
    IslandAppLib/StatusBar \
    IslandApp/IslandApp.swift \
    --glob '*.swift' \
    | rg -v 'Text\("(Dev Island|Manus|Codex)' \
    | rg -v 'groupLabel\("(Cloud Agent|Local Agents)"\)' \
    | rg -v 'SecureField\("sk-…"' \
    || true
)"
if [[ -n "$BARE_UI_COPY" ]]; then
  echo "$BARE_UI_COPY" >&2
  fail "User-facing SwiftUI copy must use L10n explicitly"
fi

rg -Fq 'defaultLocalization: "en"' "$PACKAGE" \
  || fail "Swift Package default localization must remain English"
rg -Fq '.process("Resources")' "$PACKAGE" \
  || fail "IslandAppLib localization resources must be processed by SwiftPM"
rg -Fq 'for LANGUAGE in en zh-Hans' "$BUILDER" \
  || fail "The app builder must explicitly package every supported localization"
rg -Fq 'Contents/Resources/${LANGUAGE}.lproj' "$BUILDER" \
  || fail "The app builder must copy localization catalogs into Bundle.main"

for regression in \
  testSupportedLanguageResolutionIsConservative \
  testLocalizedStringsResolveFromPackageResources \
  testMissingTranslationFallsBackToSourceKey \
  testSessionCountAndAccessibilityCopyAreLocalized \
  testEveryLocalAgentSetupSubtitleHasReviewedSimplifiedChineseCopy \
  testEnglishAndSimplifiedChineseCatalogsHaveMatchingKeys; do
  rg -Fq "$regression" \
    IslandAppLibTests/Sources/IslandAppLibTests/DevIslandLocalizationTests.swift \
    || fail "Localization regression is missing: $regression"
done

for surface in \
  "$HISTORY_PRESENTATION" \
  "$HISTORY_VIEW" \
  "$STATUS_PRESENTATION" \
  "$STATUS_ITEM" \
  "$NOTIFIER" \
  "$ACTION_PRESENTATION" \
  "$ACTION_SURFACE"; do
  test -s "$surface" || fail "Localized product surface is missing: $surface"
done

for invariant in \
  'func label(language: DevIslandLanguage = .current)' \
  'static func statusLabel(' \
  'static func relativeAgeLabel(' \
  '@Environment(\.devIslandLanguage) private var language'; do
  rg -Fq "$invariant" "$HISTORY_PRESENTATION" "$HISTORY_VIEW" \
    || fail "Session History localization contract is missing: $invariant"
done

for invariant in \
  'language: DevIslandLanguage = .current' \
  'L10n.format(key, language: language, Int64(count))' \
  'L10n.string(key, language: language)'; do
  rg -Fq "$invariant" "$STATUS_PRESENTATION" \
    || fail "Status-menu localization contract is missing: $invariant"
done
for invariant in \
  'let language = DevIslandLanguage.current' \
  'L10n.string("Open Island", language: language)' \
  'L10n.string("Check for Updates…", language: language)'; do
  rg -Fq "$invariant" "$STATUS_ITEM" \
    || fail "AppKit status-menu copy must use the app language: $invariant"
done

rg -Fq 'func title(language: DevIslandLanguage = .current)' "$NOTIFIER" \
  || fail "System notification titles must use the app language"
rg -Fq 'content.title = kind.title()' "$NOTIFIER" \
  || fail "System notifications must use the localized semantic title"

for invariant in \
  '@Environment(\.devIslandLanguage) private var language' \
  'L10n.string("APPROVAL", language: language)' \
  'L10n.format("Expires in %@", language: language, expiresIn)' \
  'language: language'; do
  rg -Fq "$invariant" "$ACTION_SURFACE" \
    || fail "Decision-surface localization contract is missing: $invariant"
done
rg -Fq 'L10n.format("Session %@", language: language, fingerprint)' "$ACTION_PRESENTATION" \
  || fail "Private session references must follow the app language"

for regression in \
  testHistoryPresentationFollowsExplicitSimplifiedChineseLanguage \
  testMenuHealthCopyFollowsExplicitSimplifiedChineseLanguage \
  testNotificationTitlesFollowTheAppLanguage \
  testSessionReferenceIsStableCompactAndDoesNotExposeRawIdentifier; do
  rg -Fq "$regression" IslandAppLibTests/Sources/IslandAppLibTests \
    || fail "Localized product-surface regression is missing: $regression"
done

echo "Localization invariants: PASS"

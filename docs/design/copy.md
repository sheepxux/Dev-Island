# Copy

Source: `IslandAppLib/Resources/{en,zh-Hans}.lproj/Localizable.strings`,
`L10n`. The localization gate (`scripts/ci/verify-localizations.sh`) fails
the build on a missing key or a bare `Text("…")`.

## Mechanics

- Keys are the English text, in sentence case. Every key exists in both
  catalogs. A key that no source file references is deleted.
- One key per meaning. "Preview" is the signal-sound button (试听); the
  Welcome's example label uses "Example" (示例). Reusing a key across
  meanings ships the wrong Chinese.
- Commands, file names and brand names are `Text(verbatim:)` and never
  translated.
- Plurals are two keys chosen at the call site:
  `L10n.format(count == 1 ? "%lld stored session" : "%lld stored sessions", language: language, Int64(count))`.
  Session counts use `L10n.sessionCount(_:language:)`. The localization gate
  only sees keys written as a literal first argument, so check both keys
  exist in both catalogs by hand.
- Some Settings keys are still Title Case ("Launch at Login", "View
  History"); `PRIVACY.md` quotes some of them, so they change together with
  the legal documents, not in a UI pass. New keys are sentence case.

## Voice

- Say what happens, in the user's words: "Needs you", "Connect the ones you
  use". Not mechanism words (Hook, hash, listener) unless the user must act
  on that mechanism, as in Codex authorization.
- Labels name the action: "Allow once", "Disconnect", "Update all". Never
  "OK", "Submit", "Confirm".
- An empty state says what will appear and offers the next step. A healthy
  state says nothing.
- A status never pretends: an example is labelled Example; configured is
  not "connected" until real activity arrives.

## English

- Sentence case everywhere, including buttons and headers.
- No em dashes in UI copy; use a period and a new sentence.
- No "please", no exclamation marks, no "successfully".
- `…` is one character. Use it for truncation and ongoing states
  ("Checking…").

## Chinese

- Match meaning, not word count. The Welcome's headlines reuse the wording
  the owner approved in the 2026-09-20 prototype (它在忙，你可以专注。).
- 请 is acceptable in error sentences ("无法连接 Manus，请重试。"), matching
  macOS's own zh-Hans register. Button labels and short status lines drop
  it: 重试, 待在 %@ 中确认.
- Use full-width punctuation in Chinese sentences and keep Latin terms
  (Agent, Hook, Codex) unspaced from punctuation.
- "Needs you" is 需要你处理, never 专注 (that is "focus").

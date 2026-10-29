# English / Simplified Chinese copy review

Reviewed on Windows, 2026-10-29, against main 8601d26: 471 entries per catalog.
Scope included onboarding, settings, connection status, usage, privacy and
diagnostics, island actions, history, system notifications, accessibility,
approval/plan/question flows, activity summaries and global shortcuts.
English values all match their source keys; no English wording changes proposed.

This PR addresses one category: translations overstating a verified outcome.

| Key | Problem | Correction |
| --- | --- | --- |
| Preview lifecycle and handle documented tool approvals | Documented became verified protocol, overstating Preview validation. | 有文档说明的工具审批 |
| Decision sent | Sent became delivered. | 决定已发送 |
| Answers sent | Sent became delivered. | 回答已发送 |

The separate managed-Hook/trust terminology corrections are in PR #29.
Product and provider names, source keys, placeholders and Swift code are unchanged.
Catalog parsing, unique/matching key sets and format-argument type counts passed.
Literal percent signs and positional placeholders were accounted for.

Remaining owner acceptance: English and Chinese snapshots on affected fixed-size
surfaces, wrapping/truncation and control widths, and the packaged Mac app.
Windows text review cannot establish layout acceptance. No claim is made that
the repository's macOS localization verifier ran locally.

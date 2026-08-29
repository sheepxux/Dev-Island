# Security Policy

Dev Island connects local developer tools, privileged approval prompts, a
third-party cloud API, and an authenticated update channel. Security reports
are welcome and should be handled privately until users can update safely.

## Supported versions

The latest published Dev Island release is the supported public version.
Security fixes may require updating to a newer release. Development builds and
unreleased branches receive no compatibility guarantee.

## Reporting a vulnerability

Prefer a private [GitHub Security Advisory](https://github.com/sheepxux/Dev-Island/security/advisories/new).
If that is unavailable, email [alsoaxu@gmail.com](mailto:alsoaxu@gmail.com) and
[puzhen913@gmail.com](mailto:puzhen913@gmail.com) with “Dev Island Security” in
the subject.

Include the affected version, macOS version, connector, impact, and the
smallest safe reproduction. Do not include API keys, private prompts, customer
data, production signing material, or an unredacted task database. The
aggregate **Settings → Support → Copy / Save Diagnostics** report is designed
to be safe to share, but review it before sending. Saving writes only to the
local path selected by the user, uses an owner-only file mode and atomic
replacement, and rejects existing links or directories; it never uploads the
report.

The maintainers will make a best-effort acknowledgement and coordinate
validation, remediation, release, and disclosure. No response-time or bounty
commitment is created by this policy.

## Research boundaries

- Test only systems, accounts, tasks, and files you own or are authorized to
  use.
- Do not target other users, Manus, Cloudflare, GitHub, Apple, Anthropic,
  OpenAI, Cursor, or their infrastructure through this project.
- Do not publish an exploit before a fix or mitigation is available to users.
- Avoid persistence, destructive actions, denial of service, social
  engineering, credential access, and unnecessary access to private data.

## High-value surfaces

- Manus API-key storage and public Webhook authentication;
- the localhost Hook boundary and browser-origin rejection;
- Claude Code, Codex, and preview Qwen Code synchronous approval responses;
- managed Hook installation and preservation of user configuration;
- Sparkle feed/archive signatures, nested code signing, release secrets,
  checksum inventory, and repository-bound SPDX/build attestations;
- task URLs, notification routing, diagnostics, and unified-log privacy.

Public Manus realtime remains disabled until the implemented official v2
protocol passes signed registration, lifecycle-event, and deletion checks
against a real account. Production Sparkle private keys must
never be committed, bundled, logged, or passed as command-line arguments.
Before any future Manus webhook registration, Dev Island must prove ownership
of its loopback listener with a private bounded challenge; a port conflict,
redirect, oversized response, or later health-check failure must fail closed
and tear down the public transport.

# Dev Island Legal and Commercial Release Checklist

Status: engineering review complete; owner/legal decisions still required.

This checklist separates facts the repository can verify from decisions that
must be made by the product owner or qualified counsel.

## Current website findings (read-only audit, 2026-08-26)

The live `devisland.app/privacy` and `/terms` pages are polished but no longer
match the product. Do not treat them as release-ready without revision:

- Privacy says task data is never transmitted off-device, while the optional
  Manus connector intentionally communicates with `https://api.manus.im`.
- Privacy describes update metadata as a JSON file; the implemented Sparkle
  channel uses an XML appcast plus an archive.
- Privacy omits local SQLite field categories, Keychain deletion behavior,
  notification content, unified logs, clipboard diagnostics, and the disabled
  Cloudflare/Manus realtime path.
- Terms grant only a personal, non-transferable, revocable app license and say
  only an adapter SDK is open source. The repository's current `LICENSE`
  applies the MIT grant to the Software and permits distribution, sublicensing,
  and sale of copies.
- The comparison page claims approximately `0.4%` average background CPU, but
  no retained unlocked 60-second sample and Time Profiler trace currently
  proves that claim. Short locked-screen diagnostics exist only for regression
  comparison and are explicitly invalid for marketing.

Local canonical replacements are `PRIVACY.md`, `TERMS.md`, and
`docs/DATA_FLOW_INVENTORY.md`. Publishing them to the website is an external
action and requires explicit owner approval.

## Decisions required before charging users

- [ ] Identify the legal seller or Merchant of Record and governing contact.
- [ ] Choose and document the relationship between the current MIT grant and
      future commercial binaries/services (MIT distribution, open core, or a
      lawfully separated future proprietary component).
- [ ] Confirm ownership/assignment for contributions needed to relicense any
      future component; existing MIT grants cannot simply be withdrawn from
      copies already distributed.
- [ ] Set price, currency, tax handling, trial length, included updates/support,
      device limit, activation transfer, refund/cancellation, revoke/refund,
      reinstall, offline grace, and account-recovery policies.
- [x] Keep every unresolved commercial choice explicit in a machine-readable
      draft and reject unknown fields, insecure provider origins, hardware
      fingerprints, contradictory trial/update rules, and incomplete approval.
      The record is descriptor-read with owner/mode/link/size/path/parent
      stability and duplicate-key rejection. `scripts/commerce/commercial-policy.json`
      remains `required`; this control does not approve any seller, price,
      trial, region, or policy.
- [ ] Review consumer-law, privacy, export/sanctions, and accessibility duties
      for the jurisdictions where sales will be offered.
- [ ] Review the final privacy notice and terms with qualified counsel.
- [ ] Publish versioned legal pages and retain the exact copy shown at each
      purchase.
- [x] Current Support actions are preceded by offline Privacy / Terms entries
      whose signed-bundle bytes are bound to the canonical bilingual drafts.
      No consent, checkout, or activation flow ships yet; any future flow must
      reuse the same versioned entry before it can pass the release gate.

## Engineering gates before publication

- [x] Source-backed data-flow inventory.
- [x] Privacy copy distinguishes local processing, Manus, updates, OS services,
      website hosting, and support email.
- [x] Terms acknowledge the actual MIT license and third-party Agent risk.
- [x] CI checks that every known data flow remains represented in canonical
      documentation.
- [x] Private vulnerability-reporting policy and explicit research boundaries.
- [x] Privacy-minimal previous-session health marker distinguishes only clean
      versus incomplete termination, never reads/uploads crash reports, and is
      included in redacted Support diagnostics.
- [x] In-app destructive confirmation for transactional deletion of persisted
      task and progress history; active sessions remain in memory.
- [x] In-app destructive confirmation for removing all managed local-Agent
      Hooks; user-owned handlers survive and cross-file failure rolls back
      without overwriting concurrent edits.
- [x] A maintainer-only hermetic listener command proves loopback
      start/challenge/stop using a random port, memory-only authorization and
      zero Agent routes. Ten CI rounds require fixed low-cardinality stdout and
      empty stderr; the fixture cannot touch production Hook configuration,
      authorization storage, Keychain, SQLite or tasks and does not replace
      real-Agent acceptance.
- [x] The real Production Bundle has a maintainer-only hermetic launch mode
      requiring an exact argument/environment pair. It renders the shipping
      island and status item from a frozen private App copy while TaskStore,
      SQLite, Keychain, local Hooks, Manus, notifications, Welcome and Sparkle
      remain inert; every one of eight survival samples checks for network
      sockets and product-state creation before exact-PID AppKit status-0 exit.
      PR CI runs it after Production build, and tag Release repeats it after App
      notarization and before DMG packaging. Locked samples never support a
      performance or smoothness claim.
- [x] Ordinary launches arbitrate same-Bundle copies before any window,
      backend or LaunchHealth write. Bundle ID only bounds candidates; valid
      dynamic code identity must also match by exact identifier plus an
      Apple-anchored same Team, or by the same CDHash only when signing flags
      explicitly mark both builds ad-hoc. At most 32 candidates
      are inspected, and the lowest older trusted PID is revalidated before
      AppKit activation. Missing/drifting identity, overload, vanished winner
      or activation failure stays fail-open. The decision reads no path,
      command, environment, window, preference, credential or IPC payload,
      persists/transmits/logs nothing, and is bypassed only by the exact inert
      hermetic Production-smoke opt-in.
- [x] Settings reads bounded Agent configuration and performs explicit
      Enable/Update/Disable writes through an on-device background worker,
      keeping JSON/TOML parsing and file/directory synchronization off the main
      actor. Only low-cardinality state and fixed error copy return to the UI;
      operation tokens are memory-only, mutations re-read actual state before
      claiming success, and this adds no network or persistence destination.
- [x] Plan Review Markdown has character and UTF-8 byte bounds; block and
      inline parsing run once per request off the main actor, and no more than
      512 complete blocks can enter SwiftUI. Approve/Reject remains disabled
      before a complete render or for an empty/over-complex document, while
      Continue in Claude stays available. Render state is memory-only and adds
      no network or persistence destination.
- [x] Disposable pinned-Sparkle old-to-new transport/install gate with signed
      feed/archive and four fail-closed corruption/key cases; it uses only
      public fixture keys and leaves no random preference/cache residue.
- [ ] Production Sparkle key custody and Developer ID/notarized old-to-new
      update evidence.
- [x] Hermetic, production-key-incompatible idle and 20-session performance
      fixture plus descriptor-owned append-never CPU/RSS sampler; the three
      outputs use atomic noclobber creation, `0600` single-link files and
      device/inode rebinding. Readiness and statistics each receive a bounded
      no-follow/nonblocking snapshot bound to the App-log or CSV writer token;
      strict readiness parsing rejects FIFO replacement, malformed/duplicate
      markers and reverse/out-of-window uptime. Summaries bind executable and
      machine identity and report
      p50/p95, memory growth, and long-run RSS slope.
- [x] Performance sampling freezes the selected signed QA Bundle into a random
      private `0700` sampler root and launches only that copy; bounded
      descriptor hashes bind executable/plist before and after copy, before
      launch and after normal termination. CI requires equal selected/private
      executable hashes plus `isolated_app_snapshot=true`, and source replacement
      fails without publishing a summary.
- [x] PR CI captures the sampler's bounded verified stdout in one shell
      variable and performs every launch-smoke/hash assertion from that
      in-process value. It never reopens the runner-temporary summary after
      producer exit, so a surviving QA descendant cannot replace the public
      file to change acceptance.
- [x] Artifact-level build-flavor isolation verifies the final lipo'd
      Production, Performance QA, and Debug executables against a closed marker
      matrix; pair mode binds Bundle IDs/plist state and 18 negative fixtures
      reject every fixed marker leak or omission.
- [x] Canonical Privacy / Terms inputs and signed-App copies have a bounded
      descriptor/UTF-8/bilingual-date/exact-byte verifier with 10 negative
      fixtures; Settings reads them offline before Support actions and limits
      outbound links to reviewed mail addresses and the product origin.
- [ ] Accepted current-run idle, 20-session, animation, sleep/wake, and long-run
      traces and reports.
- [x] Disabled-by-default, public-key-only offline verifier plus documented
      license-document threats and limitations; no production trust anchor.
- [x] Disconnected, bounded device-only Keychain primitive plus provider-neutral
      activation, storage, refund/revoke, device and recovery threat model.
- [x] Pre-provider commercial-activation sandbox uses only synthetic keys/codes,
      random numeric loopback, a real Hummingbird HTTP exchange, the production
      provider-neutral verifier/activation core, and process-memory storage.
      Signed success and unsigned fail-closed paths are covered; the shipping
      App remains statically free of its server/transport/ready route. This is
      client-wiring evidence, not provider, TLS, checkout, production-key,
      policy, real-Keychain, refund/revoke, device or recovery acceptance.
- [x] Real-loopback status/abuse fixtures collapse 400/401/404, 429 and 5xx to
      the three provider-neutral rejection cases; redirect, unknown status and
      oversized responses fail closed, never reach the redirect target and
      never store provider bodies.
- [x] Disabled HTTPS transport foundation rejects unsafe endpoint shapes,
      redirects, wrong final URL/media type/status and over-32-KiB declared or
      streamed bodies; its ephemeral credential-free request is bounded and
      cancellation-aware. It has no public initializer/factory, no shipping
      source constructs it, and cancellation evidence observes the underlying
      URLSession request stop. The selected provider's source-fixed factory,
      real DNS/TLS/service and one-time-code/abuse behavior remain a
      provider-specific launch gate.
- [x] Real-loopback operation-ownership fixtures deliberately ignore caller
      cancellation until a bounded signed response returns. Explicit Cancel
      still stores nothing; when old and new signed responses both complete,
      only the latest activation can commit. The detached mode remains test-only
      and does not approve a provider cancellation or retry protocol.
- [x] Pre-cancelled activation is rejected before operation ownership or
      transport creation. Controlled and real-loopback fixtures prove it sends
      no additional request, cannot supersede the existing owner, and cannot
      consume a one-time code through a caller that was already abandoned.
- [x] Provider-neutral commercial policy record, strict validator, and negative
      fixtures; `--require-approved` fails until owner/legal review evidence and
      every required policy field are present.
- [x] Tagged releases rerun dependency, security/privacy, full-test, and diff
      gates before importing signing identities; third-party Actions are pinned
      to immutable commits and all release tags are serialized.
- [x] Release credentials fail closed before certificate import; Developer ID
      Team ID is bound to notarization identity, and the stapled App and DMG
      must both pass hard Gatekeeper acceptance before GitHub publication.
- [x] Release publication is preceded by an atomic `SHA256SUMS` over every
      DMG/ZIP alias, signed appcast, deterministic SPDX SBOM, and generated
      Cask; aliases must be byte-identical, inputs cannot be symbolic links,
      and every published subject receives GitHub Sigstore-backed build
      provenance.
- [x] PR CI and Release generate SPDX 2.3 from all exact SwiftPM revisions,
      the compiled vendored toml++ version, all nine Agent source marks, the
      exact 18 PNGs shipped in the App, and actual bundled license notices;
      byte reproduction is mandatory and Release DMG/ZIP aliases receive a
      separate signed GitHub SBOM attestation.
- [x] A deterministic brand manifest and attack-tested verifier reject missing,
      extra, symbolic-link or byte-drifted source/raster assets; the downloaded
      Release verifier independently requires all nine brand SPDX packages and
      their exact source/bundle hashes.
- [x] All nine Agent sources now pin an immutable repository revision/path,
      upstream SHA-256 and closed transform. Lobe Icons/Primer/OpenCode MIT and
      Kimi/Qwen Apache-2.0 notices are bundled with schema-v3 content hashes;
      attack fixtures reject upstream, transform, or notice drift, and the
      SPDX/download verifier preserves those facts.
- [ ] Owner/legal trademark presentation approval for all nine Agent marks.
      Apache-2.0 section 6 does not grant general trademark permission. The
      schema-v1 review record binds every decision to the exact source,
      rendered PNGs, upstream identity, notice and four product surfaces; a
      commercial Release additionally requires unexpired `WORLDWIDE` approval
      for direct download, GitHub Release and Homebrew. All nine entries remain
      explicit blockers; the tagged workflow fails before loading Release credentials.
      See `docs/BRAND_ASSET_REVIEW.md` and the T7
      deterministic `trademark-review-pack-v2` evidence packet.
- [x] The lossless TOML parser is exactly pinned and `Package.resolved` is no
      longer ignored; Swift TOML and its bundled toml++ MIT notices are copied
      into the app and asserted by CI.
- [x] Release-pinned Homebrew Cask artifact is generated from the exact ZIP
      SHA-256; the draft zap targets the real SQLite directory, documents
      retained Keychain state, and does not force-install disabled realtime
      infrastructure. PR/tag gates render it deterministically inside an
      isolated temporary tap, run real Homebrew style/readall evaluation, and
      reject unpinned/latest downloads, install-time scripts, unsafe Keychain
      deletion, wrong Bundle IDs, versions, URLs, macOS floors or zap paths.
- [x] Repository-owned offline and published-Release verifiers require exactly
      eight regular assets, cross-check checksum/Cask/Appcast/SPDX metadata and
      tagged source revision, pin SLSA verification to the repository,
      `release.yml`, tag ref and commit, and require separate SPDX attestations
      for all DMG/ZIP aliases. Negative fixtures exercise every trust boundary;
      public v0.3.0 correctly reports as a legacy incomplete Release.
- [x] Repository-owned, GET-only GitHub controls auditor and offline fixtures
      define the required branch protection, review, required CI, exact Action
      allowlist/SHA pinning, token, secret-scanning, and Dependabot policy.
- [x] PR CI always emits a low-cardinality job summary and uploads exactly two
      sanitized diagnostic files only on failure, using a full-SHA-pinned
      GitHub-owned Action and 14-day retention; raw logs, environments,
      credentials, products, source and App data are excluded by fixtures.
- [ ] Remote `main` and repository settings pass
      `scripts/qa/audit-github-repository-controls.sh`; until then the checked-in
      PR workflow is not an enforced merge or commercial-release boundary.
- [ ] Provider-specific checkout, issuer Webhook, activation, storage,
      revocation, refund, device-limit, and recovery threat model.
- [ ] Provider sandbox activation plus checkout, refund/revoke, device-limit,
      recovery, expiry/replay/enumeration/rate-limit and outage evidence.
- [ ] A new real tagged Release for which
      `scripts/release/verify-published-release.sh` verifies the downloaded
      asset contract, GitHub build provenance, and all SBOM attestations before
      old-to-new update testing.
- [ ] Final keyboard, VoiceOver, Reduced Motion, and visual audit.

## Publication rule

No draft, payment flow, production key, external service, public Webhook,
GitHub Release, or website change is approved merely because this checklist
exists or because automated checks pass.

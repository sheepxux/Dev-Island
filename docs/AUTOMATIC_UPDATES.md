# Dev Island Automatic Update Security

Dev Island uses Sparkle 2.9.6 as an authenticated update transport. The
framework version is exactly pinned because the updater, bundle copier,
code-signing graph, appcast generator, and release verifier form one security
boundary.

## Release behavior

A production release enables updates only when `SPARKLE_PUBLIC_ED_KEY` is
present and decodes to exactly 32 bytes. The signed app then contains:

- an HTTPS-only `SUFeedURL` pointing to the latest GitHub Release appcast;
- `SUPublicEDKey` for Ed25519 archive verification;
- `SUVerifyUpdateBeforeExtraction = true`;
- `SURequireSignedFeed = true`;
- `SUSignedFeedFailureExpirationInterval = 0` so feed-signing failures never
  age into an unsigned fallback;
- `SUEnableSystemProfiling = false`;
- `SUEnableAutomaticChecks = true` and
  `SUScheduledCheckInterval = 86400` for an explicit daily default; and
- `SUAutomaticallyUpdate = false`, so installation is never silent.

Local and pull-request builds intentionally omit the feed and public key.
`AppUpdateController` validates the complete trust configuration before it
constructs Sparkle. A partial, malformed, credential-bearing, or non-HTTPS
configuration therefore leaves the updater inert. It accepts only the exact
production GitHub appcast URL documented below—not another HTTPS host, path,
query, or fragment—and requires every privacy, scheduling, signed-feed, and
installation-policy field above to be explicitly present with the safe value.

## Runtime lifecycle

Valid metadata is necessary but does not prove Sparkle can start on the current
installation. `AppUpdateController` therefore constructs
`SPUStandardUpdaterController` with `startingUpdater: false`, installs bounded
state observation, and calls Sparkle's throwing `start()` explicitly. A start
failure is reduced to the low-cardinality `.failed` state: Check Now and the
automatic-check preference are disabled, the raw Sparkle error is not logged,
rendered, persisted, or included in support diagnostics, and Settings asks the
user to restart Dev Island. The default delayed developer-facing
misconfiguration alert from `startingUpdater: true` is never used.

The product-visible state machine is `unavailable → starting → ready ↔
checking`, with `failed` terminal for the current App process. Manual checks
atomically enter `checking` before calling Sparkle, so repeated clicks cannot
start parallel sessions. A monotonically increasing runtime generation rejects
KVO callbacks already queued by a failed runtime. Keyless QA/PR builds never
construct the Sparkle runtime at all, and automatic-check preferences cannot be
mutated until an authenticated runtime has started successfully.

## One-time production key setup

Do this on a trusted offline or tightly controlled Mac. Do not perform it in
CI and do not commit either key.

1. Build or resolve Sparkle 2.9.6 and run its `bin/generate_keys` tool.
2. Export and back up the private Ed25519 key in at least two encrypted,
   access-controlled locations.
3. Add the base64 public value as the GitHub Actions secret
   `SPARKLE_PUBLIC_ED_KEY`.
4. Add the exported private value as the GitHub Actions secret
   `SPARKLE_PRIVATE_ED_KEY`.
5. Keep the private value out of shell history, issue text, logs, diagnostics,
   app resources, and repository files.

Losing the private key is a release incident: signed-feed failure is configured
to fail closed. Follow Sparkle's documented Developer ID-assisted key-rotation
procedure; never weaken or remove verification to recover quickly.

## Release pipeline

For every `v*` tag, `.github/workflows/release.yml`:

1. serializes all release tags and reruns dependencies, the disposable
   old-to-new updater gate, security/privacy invariants, the full test suite,
   and diff checks before importing signing credentials;
2. fails before certificate import unless every Apple, Developer ID, temporary
   Keychain, and Sparkle credential is present; it validates the Team ID,
   minimum temporary-Keychain password length, certificate base64, and exact
   32-byte Sparkle public-key shape, then has the private key sign the fixed
   `VERSION` payload through Sparkle's stdin-only channel and requires that
   signature to verify under the configured public key without printing either
   key;
3. requires the public key before building;
4. embeds the strict update settings before Developer ID signing;
5. signs Sparkle's nested XPC services and helpers leaf-to-root, without using
   `codesign --deep` as a signing shortcut;
6. binds the App's signed `TeamIdentifier` to the Apple Team ID used for
   notarization, then requires stapling, strict code-sign verification, and a
   hard Gatekeeper acceptance for both the App and DMG before publication;
7. packages the notarized Universal app as a versioned ZIP;
8. invokes `generate_appcast` only through the repository-owned
   `run-sparkle-appcast-generator.sh`: it moves the private key into a
   non-exported shell buffer, unsets every known release credential variable,
   starts a minimal `env -i` supervisor that remains the pinned Sparkle CLI's
   clean direct parent, excludes `HOME`, GitHub tokens and runner metadata, and
   passes the private key only through `--ed-key-file -` stdin;
9. parses both the archive `sparkle:edSignature` and the signed-feed block,
   then extracts `SUPublicEDKey` from the App inside the exact versioned ZIP and
   uses CryptoKit Ed25519 verification for the complete ZIP bytes and the exact
   feed prefix declared by Sparkle;
10. emits a release-pinned `dev-island.rb` Cask candidate from the same ZIP
    SHA-256 without publishing the external tap automatically;
11. generates deterministic SPDX 2.3 from the tagged Git revision, all 27
    locked SwiftPM packages, the exact vendored toml++ header, all nine Agent
    brand source/upstream/bundled hashes and closed transforms, and the
    hash-pinned license notices already inside the signed App, then byte-reproduces it with an
    independent `--check` pass;
12. atomically generates and verifies `SHA256SUMS` over both DMG/ZIP aliases,
    the signed appcast, SPDX SBOM, and generated Cask; stable and versioned
    aliases must be byte-identical and symbolic-link inputs are rejected;
13. stages exactly the eight public assets and runs the repository-owned
    offline verifier before upload; it rejects missing, duplicate, extra,
    symbolic-link or mismatched aliases, an incomplete/tampered manifest,
    inconsistent Cask/Appcast/SBOM metadata, an SBOM source revision that
    differs from the tagged commit, a malformed/mismatched embedded public key,
    unrelated 64-byte signatures, or any signed archive/feed byte drift;
14. asks GitHub to record Sigstore-backed build provenance for every published
    artifact and the integrity manifest;
15. creates a separate GitHub Sigstore SBOM attestation binding the SPDX
    document to both DMG and ZIP aliases; and
16. publishes `appcast.xml`, `Dev-Island.spdx.json`, `SHA256SUMS`, the Cask,
    and the DMG/ZIP assets.

Installed apps read the stable feed URL:

`https://github.com/sheepxux/Dev-Island/releases/latest/download/appcast.xml`

The appcast enclosure points to the immutable versioned ZIP belonging to the
same tag. Sparkle still verifies Ed25519 signatures and Apple code signing
before replacing the app.

For a complete post-publication check, use the repository-owned read-only
verifier. It resolves the tag commit, downloads the exact eight assets, runs
the offline cross-asset contract, then pins every GitHub attestation to this
repository, `release.yml`, the exact tag ref and source digest. DMG/ZIP aliases
also require the separate SPDX predicate:

```sh
./scripts/release/verify-published-release.sh vX.Y.Z
```

If assets have already been downloaded, the network-free core can be run
directly:

```sh
./scripts/release/verify-release-assets.sh \
  --tag vX.Y.Z \
  --asset-dir /path/to/assets \
  --source-revision TAG_COMMIT_SHA
```

The offline check now performs independent CryptoKit Ed25519 verification of
both the archive and signed feed using the public key embedded in the shipped
App. It still does not replace the production Developer ID/notarized
old-to-new installation test, Gatekeeper validation, or GitHub provenance
verification.
`SHA256SUMS` is a convenient digest inventory, not an independent signature;
repository/workflow-bound GitHub attestations provide the independent
provenance layer. The SBOM format, inventory scope, conservative license
semantics, and limitations are documented in
`docs/SOFTWARE_BILL_OF_MATERIALS.md`.

## Disposable old-to-new updater gate

After dependency resolution, both PR CI and the tagged Release preflight run:

```sh
./scripts/ci/verify-sparkle-old-to-new-update.sh
```

The gate copies the exactly pinned Sparkle 2.9.6 checkout into a random private
macOS per-user temporary root, verifies every edited source file by SHA-256,
removes unrelated remote-package references, and builds Sparkle's real framework
and `sparkle-cli` offline. The source overlay routes Sparkle's cache root and
launchd-managed helper environment into that disposable root while preserving
Sparkle's native ad-hoc helper signatures and `application-identifier`. It creates disposable
version-1 and version-2 `Dev Island.app` fixtures, requires a signed appcast and
pre-extraction verification, serves feed and ZIP only from a random
`127.0.0.1` port, then proves a real download, Ed25519 verification,
extraction, Apple code-signature validation, and in-place bundle replacement.
Four independent cases must fail without changing the old bundle: a feed
signed by another key, an archive signed by another key, an old App embedding
another public key, and an App whose signed executable was modified before the
ZIP itself was validly signed.

The fixture uses public RFC 8032 test keys and ad-hoc App signatures. Each case
has a random Bundle ID, a private runtime home, a separate private build home,
`__CFPREFERENCES_AVOID_DAEMON=1`, a 90-second process-group deadline, and a
bounded loopback server. No process receives the maintainer's real HOME or
cache/preferences path, and the gate never invokes `defaults write/delete`.
Failure cleanup can signal only `Autoupdate` or `Updater` processes whose full
command path remains inside the current random temporary root. The complete
root is removed on exit and acceptance requires private writable state with no
unsafe link or group/other-write permission. No production key, real Dev Island
installation, Agent state, GitHub Release, or remote endpoint is read or changed.

Sparkle intentionally permits Apple code-signing identity rotation when the
old Ed25519 key authenticates the archive. The disposable gate therefore tests
code-signature validity/corruption, not signer equality. The Release workflow
still binds every delivered App to its configured Developer ID Team ID, and a
real installed Developer ID/notarized old Release → new Release update remains
the final production acceptance gate.

## Verification gates

- `AppUpdateConfigurationTests` rejects HTTP, embedded URL credentials,
  alternate HTTPS destinations, malformed public keys, missing fields,
  disabled pre-extraction verification, unsigned feeds, expiring signed-feed
  failures, non-daily scheduling, silent installation, and system profiling.
  Injected runtime tests additionally prove keyless zero construction,
  idempotent explicit start, manual-check de-duplication, busy/ready recovery,
  fail-closed start errors, late-callback suppression, disabled failure-state
  controls, and preference synchronization without touching a real feed.
- `scripts/ci/verify-security-invariants.sh` guards the source, bundle, secret,
  appcast, explicit-signing, Team-ID binding, final Gatekeeper, atomic checksum
  manifest, complete asset contract, and provenance requirements. Attack
  fixtures cover missing/duplicate/extra assets, symbolic links, manifest tampering,
  byte-alias drift, Cask SHA/version/URL drift, Appcast URL/length/signature
  failures, unrelated archive/feed signatures, signed-prefix tampering,
  embedded-public-key mismatch, malformed/wrong-version SBOMs, missing or
  hash-drifted OpenCode asset components, and tagged-source mismatch.
- `scripts/ci/verify-sparkle-secret-isolation.sh` runs a real fake-generator
  subprocess with all release credential variables populated. It proves the
  exact private-key bytes arrive only on stdin, neither the generator nor its
  parent environment exposes a credential, argv/log output contains no key,
  the immutable download prefix is preserved, and missing keys, unsafe tags,
  or a symbolic-link generator fail closed.
- `scripts/ci/verify-sparkle-old-to-new-update.sh` exercises Sparkle's real
  updater, loopback download, signed feed/archive, extraction, code-signature
  validation and bundle replacement, plus four fail-closed negative chains,
  without production credentials or a remote destination.
- PR CI verifies the complete App dependency closure: every Mach-O (including
  Sparkle helpers and XPC services) must be exactly Universal, every non-system
  dependency must resolve inside the bundle, developer-machine paths and
  escaping symlinks are rejected, and eight attack fixtures must fail closed.
  Keyless CI builds must also contain no production feed or public key. CI then
  generates SPDX from the actual packaged license directory and exact
  app-production checkout and requires byte-for-byte regeneration. See
  `APP_BUNDLE_DEPENDENCY_CLOSURE.md`.
- The app bundle includes Dev Island's license, every resolved package's root
  license notice, and the reviewed OpenCode asset MIT notice under
  `Contents/Resources/ThirdPartyLicenses/`.
- The SBOM generator's built-in self-test covers deterministic output, real
  file writing, overwrite refusal, missing notices, duplicate packages,
  malformed revisions, incomplete vendored-version macros, and OpenCode asset
  SHA drift.
- A real tagged release is not accepted until
  `verify-published-release.sh` passes. Public v0.3.0 predates this contract and
  correctly fails as a legacy Release because it has only four binary assets.
  A subsequent complete tag must then pass an end-to-end update from the
  previous notarized version on a clean Mac user account.

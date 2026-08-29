# Commercial license security foundation

Status: verifier, device-local storage, provider-neutral activation core, and
commercial-policy readiness gate implemented; commercial mode remains disabled.

This document covers the offline license-document boundary and the disconnected
client activation coordinator currently implemented in `IslandCore`. It does
not approve a seller, price, trial policy, checkout provider, activation UX,
production signing key, device limit, revocation service, or change to the
repository's MIT license.

## Current behavior

- `CommercialLicenseVerifier()` contains zero trust anchors and always returns
  `commercialModeDisabled`, even if a document is supplied.
- A device-local Keychain storage primitive exists, but the app does not
  instantiate it or load a license from Keychain, disk, preferences, the
  environment, a URL, or a payment provider.
- The store is bounded to 32 KiB, uses the dedicated
  `commercial_license_v1` account, `WhenUnlockedThisDeviceOnly`, and
  `kSecAttrSynchronizable: false`. Its public import API persists bytes only
  after the verifier returns `.valid`. For the same opaque license ID, a
  signed positive `generation` may only advance, an equal generation must be
  byte-identical, and a successor's signed issuance time cannot move backward.
  The read/authenticate/compare/write boundary is serialized inside the
  process. A corrupted or currently untrusted stored document is never silently
  replaced; ordinary key rotation must overlap old/new trust until a successor
  is stored, while emergency recovery uses explicit deletion/reactivation. The
  store has no issuance, refresh, or entitlement-granting API.
- `CommercialLicenseActivationService` is provider-neutral and disconnected.
  Its injected transport has no URL, account, email, payment, device-ID, or
  retry field. The shipping app instantiates neither the service nor its
  dependencies.
- Activation codes are 16–128 bytes, use a bounded ASCII alphabet, expose no
  reusable raw-value property, and redact normal/debug descriptions. Accepted
  bytes live in one dedicated immutable allocation shared by value copies; the
  final release erases it with `memset_s` before deallocation. A keyless verifier
  rejects before transport invocation, so an inert build cannot spend a
  one-time code.
- This control erases Dev Island's accepted internal copy; it cannot erase the
  caller's original Swift `String` or copies deliberately created by a future
  provider transport. A future activation UI must clear its input state as soon
  as the bounded code is constructed, and provider-specific review must account
  for unavoidable request-body lifetime without logging or retaining it.
- New activation attempts supersede older attempts; explicit cancellation and
  caller cancellation invalidate the current attempt. A cancellation-unaware
  transport may return late but cannot reach verify-before-save persistence.
  A still-current response is evaluated against a fresh commit-time clock,
  rather than the time at which a potentially long network exchange began.
- Transport, verification, and Keychain failures are mapped to low-cardinality
  outcomes without preserving raw provider, parser, cryptographic, or storage
  errors. A signed document response also redacts its printable description.
- No production public key is present. No private signing API or private key is
  accepted anywhere in runtime sources.
- `scripts/commerce/commercial-policy.json` keeps the seller, provider, offer,
  access, lifecycle, and legal decisions explicitly unapproved. Its verifier
  accepts a structurally valid draft but rejects `--require-approved`, unknown
  fields, insecure provider origins, hardware fingerprints, contradictory
  trial/update rules, and incomplete approval evidence.
- Current beta behavior and feature availability are unchanged.

## Signed document format

The outer UTF-8 document has exactly four LF-separated lines and no trailing
newline:

```text
DEV-ISLAND-LICENSE/1
<lowercase-key-id>
<canonical-base64-payload>
<canonical-base64-ed25519-signature>
```

The Ed25519 signature covers a domain separator, format version, key ID, a NUL
delimiter, and the exact payload bytes. This prevents a signature from another
protocol or key-rotation slot from being replayed as a Dev Island license.

The payload is canonical, sorted-key JSON with exactly these fields:

- `version`
- `issuer`
- `productID`
- `licenseID`
- `generation`
- `issuedAt`
- `notBefore`
- `expiresAt`
- `tier`
- `features`

The schema intentionally contains no customer PII: no name, email address,
payment identifier, or postal address. `licenseID` is an opaque random UUID;
`generation` is a strictly positive issuer-controlled revision scoped to that
ID. The issuer must preserve the ID across refresh, upgrade, downgrade, refund,
and revoke documents whose order must remain monotonic.
Unknown, missing, duplicated, non-canonical, oversized, or malformed fields are
rejected after signature verification. Issuer, product, version, time bounds,
license ID, generation, tier, feature order, and feature uniqueness are pinned.

## Trust boundaries and assets

| Boundary or asset | Current control |
| --- | --- |
| Future issuer → untrusted document → app | Ed25519 public-key verification before semantic JSON decoding |
| Key rotation identifier | Lowercase bounded token included in the signed domain |
| Runtime trust configuration | Empty by default; no environment, preferences, network, or user override |
| Private issuer key | Out of scope and prohibited from app/runtime sources |
| Paid entitlement result | Returned only from an authenticated, product-bound, time-valid payload |
| Authenticated document → local persistence | Disconnected, bounded Keychain primitive with device-only accessibility and synchronization disabled; same-license generation replacement is monotonic and process-serialized |
| Activation code → future provider transport | 16–128 byte bounded secret, one shared dedicated allocation, scoped byte access, `memset_s` erase on final release, redacted descriptions, no endpoint in the core |
| Untrusted transport response → verifier/store | Configured-verifier preflight, latest-operation-wins, cancellation invalidation, commit-time validity evaluation, low-cardinality errors, verify-before-save only |
| Customer identity | Not represented in the license payload |

## Abuse paths and limitations

| Risk | Priority | Present mitigation or limitation |
| --- | --- | --- |
| Modify tier/features/expiry | High | Any byte change invalidates the Ed25519 signature |
| Substitute a key ID or reuse another signed protocol | High | Key ID and domain separator are part of signed bytes |
| Parser ambiguity, duplicate fields, or oversized input | Medium | Exact four-line envelope, canonical Base64/JSON, exact keys, 32 KiB/8 KiB limits |
| Production private-key theft | Critical if commercial mode launches | Cannot be solved in the app; future issuer must use isolated key custody, rotation, backup, access logs, and an incident runbook |
| Share a valid offline license | Medium | Not prevented by an offline bearer document; device policy and privacy trade-offs require an owner decision |
| Patch the local binary to bypass checks | Medium | A device owner can modify a client they control, especially an MIT build; protect server-side value on the server and do not promise DRM |
| Roll the system clock backward | Medium | Offline wall-clock expiry cannot fully resist an administrator; a future grace/refresh policy must define behavior |
| Refund, chargeback, or revocation while offline | Medium | No live revocation exists; future policy must choose signed denylist, periodic refresh, or an explicit offline grace window |
| Replay an old but still-valid document | Low/Medium | Same-license rollback is rejected across launches by signed positive generation, byte-identical equal-generation semantics, and nondecreasing signed issuance time. Switching to a different license ID is an explicit entitlement replacement, so the issuer must preserve IDs for one entitlement lineage and define transfer/recovery behavior |
| Spend a one-time code from an inert/keyless build | Medium | Service checks the configured verifier before invoking transport |
| Late transport response overwrites newer/cancelled state | Medium | Actor owns one pending operation; superseded/cancelled operation state is checked before the synchronous verify-before-save boundary, and the response is time-validated only at commit |
| Multiple client processes write the same Keychain account | Low/Medium | One process serializes read/authenticate/compare/write. Security.framework has no generic-password compare-and-swap, so any future second writer requires an explicit inter-process protocol before launch |
| Raw activation or provider error leaks through diagnostics or stale process memory | Medium | Code and response descriptions redact; public outcomes contain only bounded enums and no underlying Error; accepted bytes share one allocation that is actively erased on final release |
| Caller or future transport retains another activation-code copy | Medium | Internal storage is shared and erased, but cannot erase the caller's original Swift `String` or a provider-created request body; future UI/transport review must minimize those lifetimes and prohibit persistence/logging |
| License document disclosure | Low | Payload has no PII or payment data, but it remains a bearer entitlement and should be stored as a secret |

## Required gates before enabling commercial mode

1. Resolve the legal relationship between MIT source and any paid distribution
   or service, then approve seller, price, trial, refund, device, transfer,
   support, update, and recovery policies.
2. Threat-model the chosen checkout, webhook issuer, activation, storage,
   revocation, refund, and recovery flows with their real provider contracts.
3. Build a separate issuer service. Keep its Ed25519 private key outside the
   repository, App bundle, build logs, command arguments, artifacts, and client
   crash reports. It must keep one license ID across an entitlement lineage and
   allocate strictly increasing generations for every superseding document.
4. Inject only a reviewed public key through a deliberate source/release change;
   the current CI guard must fail until that change is reviewed together with
   tests and documentation.
5. Add a reviewed provider-specific transport around the existing activation
   coordinator. Keep its code out of URLs/query/logs, preserve generic
   rejections, and use the existing verify-before-save Keychain primitive with
   its dedicated `ThisDeviceOnly`/non-synchronizing controls.
6. Complete sandbox purchase, activation, restart/offline, expiry, refund,
   revoke, key-rotation, corrupt-input, clock-change, migration, and recovery QA.
7. Update `PRIVACY.md`, `TERMS.md`, the live website, support material, and the
   data-flow inventory before any public paid release.

## Evidence

- Verifier: `IslandCore/Sources/IslandCore/Commerce/CommercialLicenseVerifier.swift`
- Attack-focused tests:
  `IslandCoreTests/Sources/IslandCoreTests/CommercialLicenseVerifierTests.swift`
- Device-local store:
  `IslandCore/Sources/IslandCore/Commerce/CommercialLicenseDocumentStore.swift`
- Keychain attack/regression tests:
  `IslandCoreTests/Sources/IslandCoreTests/CommercialLicenseDocumentStoreTests.swift`
- Provider-neutral activation coordinator:
  `IslandCore/Sources/IslandCore/Commerce/CommercialLicenseActivation.swift`
- Activation attack/concurrency tests:
  `IslandCoreTests/Sources/IslandCoreTests/CommercialLicenseActivationTests.swift`
- Provider-neutral commercial flow model:
  `docs/COMMERCIAL_ACTIVATION_THREAT_MODEL.md`
- CI invariants: `scripts/ci/verify-security-invariants.sh`

The tests use ephemeral private keys created only inside the test process. They
verify tampering, protocol confusion, key-ID substitution, raw-signature reuse,
unknown keys, malformed/oversized envelopes, canonical encoding, exact schema,
positive generation and time boundaries, disabled-by-default behavior,
device-only/non-synchronizing Keychain semantics, signed rollback and
equal-generation conflict rejection, expired-document revision preservation,
concurrent-import serialization, replacement preservation, idempotent deletion,
oversized stored-document rejection, activation-code validation/redaction,
shared secret allocation and `memset_s` erasure, configured-verifier preflight,
error normalization, successful Keychain round-trip, latest-operation-wins,
commit-time expiry, and cancellation-unaware late responses.

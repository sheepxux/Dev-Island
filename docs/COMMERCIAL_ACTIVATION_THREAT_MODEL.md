# Dev Island Commercial Activation Threat Model

Status: provider-neutral controls defined; provider selection, production
services, commercial policy, and launch approval remain open.

Date: 2026-08-31

## Scope and non-goals

This document defines the minimum security contract for a future paid Dev
Island distribution or service. It covers checkout events, entitlement
issuance, activation, device limits, local storage, refresh, refund/revocation,
transfer, and recovery. It is grounded in the current offline verifier and
disconnected Keychain store:

- `IslandCore/Sources/IslandCore/Commerce/CommercialLicenseVerifier.swift`
- `IslandCore/Sources/IslandCore/Commerce/CommercialLicenseDocumentStore.swift`
- `IslandCore/Sources/IslandCore/Commerce/CommercialLicenseActivation.swift`

No checkout provider, Merchant of Record, account system, device limit,
offline grace period, refund policy, issuer service, or production key has been
approved. This model does not enable commercial mode and does not change the
repository's MIT license.

## Current security state

- The shipping app creates neither a configured verifier nor a commercial
  document store. With zero trust anchors it returns
  `commercialModeDisabled`.
- The signed document contains no name, email, payment identifier, hardware
  identifier, or postal address. It includes one strictly positive signed
  generation scoped to the opaque license ID.
- A device-local Keychain primitive exists for an already authenticated bearer
  document. It uses a dedicated account, `WhenUnlockedThisDeviceOnly`, and
  `kSecAttrSynchronizable: false`; its public import persists only a verifier
  `.valid` result. Same-license replacements are generation-monotonic,
  equal-generation documents must be byte-identical, a successor's issuance
  time cannot move backward, and the read/compare/write path is serialized
  inside one process. The app does not instantiate it.
- A disconnected provider-neutral activation actor accepts only 16–128 byte
  bounded ASCII codes, redacts printable representations, rejects a keyless
  verifier before transport, normalizes every error, and enforces
  latest-operation-wins/cancellation before verify-before-save persistence and
  checks document expiry using a fresh commit-time clock after transport.
  It has no URL, provider, account, email, payment data, device identifier, or
  production trust anchor, and the app does not instantiate it.
- A separate disabled-by-default HTTPS transport foundation now exists in
  shipping `IslandCore`, but the App and AppLib do not construct it and it has
  no hard-coded endpoint. It exposes no public initializer or factory; the
  module-internal endpoint constructor is reachable only from `IslandCore`
  tests until a reviewed, source-fixed provider factory is deliberately added.
  No shipping `IslandCore`, App, or AppLib source constructs it. Its initializer
  rejects non-HTTPS, non-DNS, reserved,
  alternate-port, userinfo, alternate-path, query and fragment destinations.
  The ephemeral session disables proxy/cookie/cache/ambient credentials,
  connectivity waiting and redirect following, uses a ten-second bound, sends
  the code only in the POST body, rebinds the final URL, validates status/media
  type, and enforces the shared 32 KiB response limit while iterating bytes.
  URLSession's normal platform TLS and hostname validation are not overridden;
  caller-cancellation regression evidence observes the underlying URLProtocol
  request's `stopLoading`, not merely a cancelled wrapper result.
- A pre-provider test-only loopback sandbox now drives that actor through a
  real Hummingbird TCP/HTTP request. It creates an ephemeral Ed25519 key,
  synthetic privacy-minimal document, random numeric `127.0.0.1` endpoint and
  process-memory document backend. The transport rejects every non-exact local
  endpoint and disables proxy, cookie, cache and redirect behavior. A signed
  response must verify and persist in memory; an unsigned response must become
  `licenseRejected` with zero storage. None of these types are linked into the
  shipping App, and the sandbox never accesses the login Keychain.
- The same real-HTTP fixture now proves 400/401/404 collapse to one code
  rejection, 429 to rate limiting, and 5xx to service unavailability without
  returning or storing provider-private bodies. Redirect, unknown-status and
  oversized-response cases fail as transport unavailable, never reach a
  redirect target and leave storage empty. Missing or zero ports are rejected
  alongside every other non-exact endpoint.
- A cancellation-insensitive attack mode keeps its loopback URLSession request
  in a detached but two-second-bounded task. The server therefore returns the
  signed response after explicit Cancel or supersession instead of letting
  cooperative network cancellation make the test pass. Recorder counts prove
  one late response is rejected with no document, and that when both old/new
  responses return only the latest operation reaches verify-before-save.
- A caller already cancelled before entering the activation actor owns no new
  operation. Controlled and real-HTTP regressions prove it creates no transport
  request, cannot supersede the existing owner, and leaves that original signed
  response eligible to activate.
- There is no configured issuer/activation endpoint, refresh endpoint, checkout
  Webhook, account recovery path, administrative entitlement tool, production
  trust anchor, or runtime commercial-service instantiation.

This loopback sandbox closes only the in-process client-wiring gap between the
transport protocol and the existing verifier/store. Because it deliberately
uses plain HTTP on numeric loopback, synthetic one-use inputs and no provider,
it is not evidence for TLS/server identity, checkout or Webhook authenticity,
code issuance/expiry/replay/enumeration/rate limits, refunds, revocation,
device limits, recovery, production key custody, real Keychain behavior or
operations. Those controls remain mandatory before commercial mode can ship.
The fixture buffers its synthetic local response before enforcing the 32 KiB
document limit; it therefore remains only actor-wiring evidence. The shipping
HTTPS transport independently enforces both declared and unknown response
lengths while reading, but its URLProtocol fixtures are not evidence for a real
provider certificate, DNS, endpoint, service behavior or abuse controls.
The detached cancellation-insensitive mode is an adversarial test mechanism,
not a production cancellation design or a reason to detach real network work.

## Required future topology and trust boundaries

| Boundary | Untrusted input or asset | Required control before launch |
| --- | --- | --- |
| Browser → checkout provider | Customer and payment data | Provider-hosted checkout; Dev Island must not handle card data |
| Provider → issuer Webhook | Raw request body, signature, event ID and time | Provider's documented raw-body signature verification, timestamp window, event allowlist, durable replay table, fail-closed parsing |
| Issuer → entitlement database | Purchase/refund/revoke/transfer events | Idempotent state transition keyed by provider event ID and internal entitlement ID; transactional audit record |
| App → activation API | Single-use code and optional device registration | Client core bounds/redacts codes, preflights trust, rejects pre-cancelled calls before operation ownership/transport, exposes generic outcomes and rejects stale/cancelled responses. Disabled HTTPS foundation has no public constructor, adds exact body-only endpoint, platform TLS, no redirect/cookie/cache/credentials, ten-second timeout and streaming response bound, and propagates caller cancellation to URLSession work; provider must still add a source-fixed factory and prove its exact domain/certificate, short expiry, one-time redemption, rate limits and non-enumerating behavior |
| Issuer → signed license | Tier, features, validity, opaque license ID and generation | Isolated Ed25519 key custody, domain-separated canonical document, stable ID per entitlement lineage, strictly increasing generation/supersession policy |
| Signed license → app verifier | Bearer document controlled by the user | Authenticate before parsing semantics or persisting; pin issuer/product/key ID; bound size and canonical encoding |
| App → Keychain | Authenticated bearer document | Dedicated account, `WhenUnlockedThisDeviceOnly`, no sync, no clipboard/log/diagnostic inclusion, monotonic same-license replacement, one-process writer until an inter-process protocol exists, explicit removal |
| App → refresh/recovery API | Entitlement ID, refresh proof, optional device pseudonym | TLS, authentication independent of bearer document alone, rotation, rate limits, generic errors, data minimization |
| Support/admin → entitlement service | Refund, revoke, transfer and recovery actions | Least privilege, phishing-resistant MFA, reason codes, approval for high-impact bulk actions, immutable audit trail |

Runtime behavior, checkout/issuer services, CI/release signing, and test fixtures
are separate trust domains. Test keys and sandbox provider secrets must never be
accepted by production services or bundled in a release.

## Assets and realistic attackers

High-value assets are the issuer private key, provider Webhook secret, account
and entitlement integrity, activation/refresh credentials, signed bearer
documents, refund and device state, audit history, and production release
artifacts.

Realistic attackers include a customer controlling their Mac and network, a
party who obtains a copied license or activation code, an internet client
probing public activation endpoints, a forged/replayed provider request, a
compromised support account, and an attacker who obtains a server or CI secret.
The client cannot prevent its owner from patching an MIT-licensed local binary;
server-side value must be authorized on the server.

## Prioritized abuse paths

| Priority | Abuse path and impact | Existing control | Required mitigation/evidence |
| --- | --- | --- | --- |
| Critical | Issuer private key theft creates arbitrary valid licenses | Private keys are absent from the repo and runtime API | KMS/HSM or isolated signing worker, non-exportable or tightly scoped key, rotation/backup/incident runbook, access alerts and two-person recovery |
| High | Forged or replayed checkout Webhook grants or restores entitlement | No provider integration exists | Verify the exact raw body before decoding, enforce timestamp tolerance, durable event-ID uniqueness, event allowlist, provider sandbox attack tests |
| High | Refund/revoke races with delayed purchase events and re-enables access | No state machine exists | Monotonic entitlement generation plus provider event ordering policy; terminal revoke must not be overwritten by an older event |
| High | Stolen activation code or bearer document activates another device | Document is signed and privacy-minimal; activation code is bounded/redacted and never logged by the client core, but both remain bearer material | Single-use short-lived activation code, never place it in URLs/logs, optional owner-approved device policy, rotate on recovery |
| High | Support/admin compromise silently transfers or grants licenses | No admin surface exists | Least privilege, strong MFA, scoped actions, immutable audit, anomaly alerts, approval for bulk/high-risk operations |
| Medium | Offline client keeps using a refunded, revoked, or superseded license | Offline verifier has no live revocation | Owner-defined maximum offline grace; signed short-lived documents or signed denylist/refresh proof; explicit last-known-good and failure behavior |
| Medium | Device identifier becomes a stable cross-service tracking ID | Current schema contains no device ID | If binding is chosen, generate a random per-install pseudonym in device-only Keychain; never use serial number, MAC address, advertising ID, username, or hardware fingerprint |
| Medium | Activation/account enumeration enables credential attacks | No public endpoint exists | Uniform responses and timing, per-IP/account/code rate limits, abuse monitoring, bounded payloads, no customer existence in errors |
| Medium | Local clock rollback extends an expired document | Offline verifier uses wall clock and documents the limitation | Bound offline validity; record last trusted server time without treating local state as tamper-proof; refresh when policy requires |
| Medium | Invalid or oversized document exhausts parsing/storage or replaces a valid one | 32 KiB envelope bound, authenticate-before-semantic-parse, HTTPS response bound while streaming, verify-before-save Keychain API; deterministic tests preserve the last valid document | Provider-specific fuzz, corrupt-input and real-service streaming tests |
| Medium | Older signed document rolls back a refresh/refund/downgrade across launches | Positive signed generation, byte-identical equal-generation rule, nondecreasing issuance time, and process-serialized compare/write reject rollback for one stable license ID | Issuer must preserve the ID across one entitlement lineage; provider tests must prove ordered refresh/refund/revoke documents and recovery semantics |
| Medium | Older concurrent or explicitly cancelled activation returns late and replaces newer state | Activation actor cancels and invalidates previous operation; only the still-current operation reaches synchronous verify-before-save and uses commit-time validity | Preserve latest-operation-wins, in-flight expiry, and late-response regression tests in every provider integration |
| Low/Medium | A second process races the same Keychain item | The current client serializes writers only inside one process; Security.framework exposes no generic-password compare-and-swap | Keep one shipping writer or add and attack-test an explicit inter-process ownership protocol before any helper/CLI writes this account |
| Medium | Production and sandbox credentials or events cross environments | No service exists | Separate accounts, keys, databases, domains and bundle configuration; production rejects sandbox issuer/key IDs and vice versa |
| Low/Medium | License, email or payment metadata leaks through logs, URLs, diagnostics or crash reports | Current signed payload has no PII; runtime has no integration | Structured redaction tests, secret scanning, no raw Webhook body or activation code logging, retention and deletion policy |
| Low/Medium | Patched local app bypasses feature checks | Not preventable on an owner-controlled MIT client | Do not claim DRM; keep server-hosted paid value server-authorized and design graceful degradation for local-only features |

## Entitlement transition contract

The future issuer must define a monotonic internal entitlement generation and
place that positive generation in the signed client document. One opaque
license ID must remain stable across every ordered document in that entitlement
lineage. A transition may be retried with byte-identical output, but an older
event or document must never overwrite a newer generation.

| Event | Authoritative transition | Required client outcome |
| --- | --- | --- |
| Verified payment | inactive → active at generation N | Issue a short-lived activation code; do not email a reusable bearer document by default |
| Renewal | active N → active N+1 | Rotate/refresh validity without changing customer identity in the document |
| Refund or chargeback | active N → revoked N+1 | Refuse new activation immediately; existing offline document follows the disclosed grace policy |
| Cancellation at period end | active N → expires at N+1 | Preserve access only until the paid-through boundary |
| Device transfer | active N → active N+1 with old registration retired | Require authenticated account/recovery proof; rotate activation material |
| Account recovery | active N → active N+1 | Invalidate outstanding activation codes and refresh credentials before issuing replacements |
| Key compromise | any → incident generation | Stop issuance, publish reviewed key rotation/revocation response, ship an authenticated app update if trust anchors change |

## Device-limit options requiring owner approval

| Option | Security/privacy trade-off |
| --- | --- |
| No device binding | Best privacy and offline behavior; valid bearer licenses can be shared |
| Account-counted devices | Supports transfer and revocation; requires an account service and disclosed device records |
| Random per-install pseudonym | Avoids hardware fingerprinting and is resettable, but reinstall/recovery semantics must be explicit |
| Hardware fingerprint | Rejected baseline: brittle, invasive, difficult to recover, and creates unnecessary tracking risk |

Until a policy is approved, the signed payload and client storage must remain
device-agnostic and commercial mode must stay disabled.

The unresolved policy is now represented by
`scripts/commerce/commercial-policy.json` rather than implicit TODOs. Normal CI
validates the draft and attack fixtures; `--require-approved` remains a hard
failure until the owner/legal record is complete. The schema cannot express a
hardware fingerprint or a non-HTTPS checkout, Webhook, or activation origin.
The release verifier also anchors one `O_NOFOLLOW` file snapshot, rebinds the
final path and parent directory after reading, and rejects duplicate JSON keys
at every object depth. This prevents path replacement or parser
last-key-wins ambiguity from changing which Seller, Provider, price, or legal
decision reaches the approval gate.

## Required current-run evidence before enabling payments

1. Provider contract and exact production/sandbox domains, signature scheme,
   timestamp/retry semantics, event types, refund/chargeback behavior, and data
   retention are reviewed and recorded.
2. Sandbox tests prove valid payment, duplicate and out-of-order Webhooks,
   forged signature, stale timestamp, unknown event, refund, chargeback,
   cancellation, and provider outage behavior.
3. Current client tests prove code format/redaction, HTTPS endpoint policy,
   exact body/header contract, redirect refusal, status/media-type/final-URL
   validation, declared/unknown-length streaming bounds, cancellation,
   verifier preflight,
   normalized failures, verified-before-save, Keychain round-trip,
   same-license generation monotonicity under concurrent imports,
   latest-operation-wins, commit-time expiry, and cancelled late-response
   rejection. Provider sandbox tests must additionally prove code expiry,
   one-time use, replay rejection, enumeration resistance, rate limits, and
   offline restart.
4. Device tests prove limit enforcement, transfer, reinstall, lost-device and
   recovery behavior without collecting a hardware fingerprint.
5. Key tests prove issuer rotation, compromised-key response, production/test
   separation, and that private material never enters the app, repository,
   build log, command arguments, artifacts, analytics, or crash reports.
6. Legal and support copy disclose seller, price/tax, trial, paid-through date,
   refund/cancellation, device limit, offline grace, updates/support, recovery,
   privacy, and the actual MIT relationship.
7. Production monitoring and runbooks cover Webhook lag/failure, activation
   abuse, signing errors, entitlement drift, refund backlog, support takeover,
   and emergency disable/rotation.

Passing repository tests proves only the client-side foundation. It cannot
prove a future provider, issuer service, policy, or operational control.

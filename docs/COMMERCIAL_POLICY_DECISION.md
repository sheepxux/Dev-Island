# Commercial policy decision record

Status: owner and legal decisions required. The shipping app remains free and
commercial mode remains disconnected.

`scripts/commerce/commercial-policy.json` is the machine-readable decision
record for the future paid offer. It deliberately contains no placeholder
price, trial duration, seller, provider, device rule, or legal approval. A
placeholder that merely compiles is not a product policy and must not enable
payments.

## What is now enforced

`scripts/release/verify-commercial-policy.rb` validates both incomplete drafts
and final records. It rejects unknown fields, unbounded values, insecure or
credential-bearing provider origins, hardware fingerprints, contradictory
trial/update rules, partial approvals, symbolic links, and an unapproved record
when `--require-approved` is requested.

The record is now read from one bounded `O_NOFOLLOW` descriptor rather than a
path-based `lstat`/`binread` pair. The verifier requires a current-user-owned,
single-link, non-group/other-writable regular file under an equally private
real parent directory, freezes file/path/parent metadata across the read, and
rejects root or nested duplicate JSON keys before interpreting any decision.
Symlink, hard-link, unsafe-mode, empty, oversized, directory, parent-symlink,
duplicate-key, and deterministic post-open replacement fixtures preserve this
boundary. Failure output never includes policy contents or fixture paths.

The normal security gate validates the draft and its negative fixtures. It does
not treat the current `decisionState: required` as approval. Provider wiring,
production trust anchors, purchase/activation UI, and commercial launch remain
forbidden by the existing security invariants until this record is genuinely
reviewed.

## Decisions the owner must make

| Area | Required decision | Working recommendation, not approved |
| --- | --- | --- |
| Seller | Legal seller, jurisdiction, support contact, direct seller vs Merchant of Record | Prefer a Merchant of Record if its contract, regions, refunds, data handling, and webhook guarantees pass review |
| Provider | Exact checkout, webhook and activation origins; residency and retention | Compare current provider contracts and sandbox behavior; do not select from marketing pages alone |
| Offer | One-time vs subscription, exact price/currency, trial, included updates and support | A simple one-time offer with a humane full-feature trial is easier to understand; final numbers require owner approval |
| Access | Device limit, identity, transfers, reinstall, offline grace and recovery | Never use a hardware fingerprint; prefer a resettable random install ID or provider account record |
| Lifecycle | Refund window, cancellation, refund/chargeback effect | Match provider and consumer-law obligations; disclose when offline access ends |
| Legal | Sales regions, Terms/Privacy versions, relationship to the existing MIT grant | Preserve the actual MIT grant and describe any future paid service or separately owned component precisely |

## Approval procedure

1. Review the seller/provider contract and record exact production and sandbox
   origins, event semantics, retention, tax, refund and dispute behavior.
2. Decide the offer and lifecycle policies in plain customer-facing language.
3. Have the seller authority and qualified legal reviewer approve the exact
   record, Terms, Privacy notice, and supported sales regions.
4. Replace only the `null`/empty draft values, set `decisionState` to
   `approved`, and record UTC review time, reviewer and immutable review
   reference.
5. Run the verifier with `--require-approved`, then complete provider-specific
   checkout, Webhook, activation, refund/revoke, device and recovery sandbox
   evidence before connecting the App UI or production trust anchor.

The verifier proves record completeness and internal consistency. It does not
prove that a commercial decision is lawful, fair, supported by the provider,
or approved by the named reviewer.

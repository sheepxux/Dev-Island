# Dev Island Brand Asset Review

Status: immutable-source provenance and repository-backed asset-license
assertions are complete for all nine shipped marks. Owner/legal trademark
approval is still required before a commercial Release.

Dev Island displays third-party names and marks only to identify the Agent a
user chose to connect. That product purpose does not by itself establish the
right to redistribute every source asset or approve every trademark use.

## Fail-closed release boundary

`scripts/assets/agent-logos/manifest.json` schema v3 is the machine-readable
source of truth for all nine Agent marks. It binds each source SVG to an
immutable repository revision/path, the SHA-256 of the upstream bytes, one of
four audited transforms, the two raster PNGs actually shipped in the App, and
the SHA-256 of the exact license/notice file copied into the App.
`scripts/release/verify-brand-assets.rb` reconstructs the upstream bytes
offline and rejects missing, extra, symbolic-link, renamed, transformed, or
byte-drifted assets.

`scripts/assets/agent-logos/trademark-reviews.json` schema v1 is the separate
human-decision record. Each entry carries a SHA-256 fingerprint over the
complete presentation contract, source SVG, generated 1×/2× PNGs, immutable
upstream identity, transform, license and bundled notice. Any change to those
inputs invalidates the review instead of silently inheriting an old approval.

Normal builds and PR CI require a complete, internally consistent inventory.
The tagged Release workflow additionally passes `--require-release-reviewed`.
It stops before release credentials are loaded unless every entry has:

- `provenanceReview: reviewed`; and
- `trademarkReview: approved` in the asset manifest;
- a matching `decision: approved` in the trademark review record;
- reviewer name, reviewer role, UTC review time, authority reference and an
  immutable `sha256:…` evidence reference;
- unexpired `WORLDWIDE` coverage; and
- all three intended channels: `direct-download`, `github-release`, and
  `homebrew`.

This is intentionally stricter than successful compilation. Changing a logo,
adding an Agent, regenerating a PNG, or flipping only the manifest status
cannot silently bypass review.

## Current review state

| Agent mark | Immutable upstream source | Asset/license evidence | Trademark review | Release state |
| --- | --- | --- | --- | --- |
| Claude Code | Lobe Icons static SVG 1.94.0, commit/path/hash pinned | MIT notice bundled | Required | Blocked |
| Codex | Lobe Icons static SVG 1.94.0, commit/path/hash pinned | MIT notice bundled | Required | Blocked |
| GitHub Copilot CLI | Primer Octicons commit/path/hash pinned | MIT notice bundled | Required | Blocked |
| Cursor | Lobe Icons static SVG 1.94.0, commit/path/hash pinned | MIT notice bundled | Required | Blocked |
| Gemini CLI | Lobe Icons static SVG 1.94.0, commit/path/hash pinned | MIT notice bundled | Required | Blocked |
| Kimi Code CLI | Kimi Code 0.38.0 commit/path/hash pinned | Apache-2.0 subproject license notice bundled and hash-pinned | Required | Blocked |
| Manus | Lobe Icons static SVG 1.94.0, commit/path/hash pinned | MIT notice bundled | Required | Blocked |
| OpenCode | OpenCode 1.18.23 commit/path/hash pinned | MIT notice bundled | Required | Blocked |
| Qwen Code | Qwen Code 0.22.0 commit/path/hash pinned | Apache-2.0 license + Desktop Shell NOTICE + modification notice bundled and hash-pinned | Required | Blocked |

All nine entries now have `provenanceReview: reviewed`; every mark deliberately
retains `trademarkReview: required`. Provenance review establishes where the
checked-in bytes came from. It does not grant trademark permission or imply
vendor affiliation.

## Pinned provenance and transforms

The five Claude Code, Codex, Cursor, Gemini CLI and Manus sources are pinned to
`lobehub/lobe-icons` commit
`fbd2d56e3f734e889f1373e71c8368cc4e60e0d7`, tag
`@lobehub/icons-static-svg@1.94.0`. npm reports the same `gitHead`; the package
tarball SHA-256 is
`a813cbb544624f51344ceab00b21c3fb0e760a989453ca447c502098698b1ec2`
and its registry integrity is
`sha512-Inx1TYkjLH6YeHOIHeVW9+OM/xxRnk8TmcQVKquFUDBmE3X9sUuRGt7kALrrDBNNAbrWz7Qq6fAiFj9E9Mmw9Q==`.
The package declares MIT and its LobeHub notice is bundled in the App.

Transforms are closed rather than free-form:

- `identity` requires the checked-in source hash to equal the pinned upstream
  hash byte for byte;
- `append-trailing-lf` permits exactly the local terminal LF used by the
  Gemini CLI source and verifies the upstream hash after removing it;
- `octicons-template-v1` reverses only the reviewed Copilot root sizing,
  `currentColor`, title and terminal-LF adaptation, then hashes the original
  Octicons SVG; and
- `qwen-template-v1` reverses only `currentColor` to the upstream
  `#6D44E8` fill before hashing.

The attack fixtures mutate the upstream hash, transform name, and a packaged
brand notice. A successful local build therefore cannot silently turn an
arbitrary local SVG or changed attribution file into “reviewed” provenance.

Kimi Code's pinned SVG lives under `apps/vscode`. At the same revision that
subproject declares `Apache-2.0` in `package.json` and includes its own Apache
2.0 `LICENSE` (upstream SHA-256
`58d1e17ffe5109a7ae296caafcadfdbe6a7d176f0bc4ab01e12a689b0499d8bd`).
The packaged copy adds only a terminal LF and is pinned in schema v3 as
`cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30`.

Qwen Code's pinned SVG lives under `packages/desktop-shell`. The exact
revision's root Apache 2.0 `LICENSE` has SHA-256
`55367b61ccd2a016a0159ad886bd66a3ee6cb5e873d0c75c803c897dd245b075`;
the Desktop Shell `NOTICE` has SHA-256
`63ec46cba8da7cf6c99dc6faef3d96f23e79bb42423f67c5d3fde86dc004d67c`.
The packaged combined notice also records Dev Island's reviewed
`#6D44E8` → `currentColor` adaptation and is pinned as
`fa668918263f754d5339c3fd84fb65123525e48db72cfbbb3fff250d3775afeb`.

`NOASSERTION` remains the fail-closed SPDX boundary for any future asset whose
terms cannot be established. None of the current nine asset packages now use
that license value. A repository copyright license still does not settle
trademark policy.

## Approval procedure

For each blocked mark:

1. Record an immutable official repository URL, 40-character revision, asset
   path, upstream SHA-256, audited transform, and product version where
   available.
2. Reconstruct and hash the upstream SVG from the checked-in source; separately
   review the deterministic raster conversion in `scripts/make-agent-logos.swift`.
3. Identify the terms that apply to redistribution of the asset, ship any
   required notice, and keep uncertain SPDX fields as `NOASSERTION`.
4. Have the owner or qualified counsel review nominative use, presentation,
   attribution, and non-affiliation wording for the intended sales regions and
   all intended distribution channels.
5. Preserve the signed decision and exact screenshot evidence, record its
   SHA-256, then fill reviewer identity/role, UTC time, authority, regions,
   channels, conditions and optional expiry in `trademark-reviews.json`.
6. Change the matching manifest `trademarkReview` to `approved` only after the
   complete decision exists; rerun brand inventory fixtures, the full test
   suite, SBOM generation/check, and the complete Release verifier.

## Owner/legal review packet

The current deterministic review packet is stored outside the repository at:

`/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/release/trademark-review-pack-v2/`

It contains all nine source SVGs, all 18 rendered PNGs, the five applicable
license/notice files, copies of both machine records, a reviewer form, four
current product screenshots, a machine-readable packet manifest and
`SHA256SUMS`. The screenshot evidence is:

| Surface | SHA-256 |
| --- | --- |
| Welcome | `6e2e9ecc009b42a8c3ba7ca61774a7f0c0509240437a02661fdd52dc0bc0be69` |
| Priority panel | `5126bf4b9ce13aedb7755ac4ecd17d2471abb8449e08949c47425f018513b742` |
| Session History | `664b8acd7e79bab53e0b68b40c616f83aee836e27aa6d0357ab72514cebeb309` |
| All Agent badges | `138b415690cb9ae8fc48f99ac2fdae460634ce0d1deeffda284d445d692303bd` |

The packet is review input, not an approval. All nine checked-in decisions
remain `required` until the product owner or qualified counsel returns an
explicit decision with authority for the stated scope.

The packet is generated atomically with
`scripts/release/generate-trademark-review-packet.rb`. The generator first runs
the repository brand verifier, refuses existing output, symbolic-link inputs or
parents, missing/non-PNG screenshots and incomplete notices, then hashes every
output before one final rename. Release-foundation fixtures prove deterministic
output and reject missing evidence, overwrite attempts, symbolic links,
post-generation tampering and invalid image inputs.

Generator, fixture and reproduction evidence is retained at:

`/Volumes/T7 Shield/MacMini/CodexFiles/DevIsland-Optimization/evidence/release/trademark-review-packet-generator-v1/TRADEMARK_REVIEW_PACKET_EVIDENCE.md`

This document and the automated gate are evidence controls, not legal advice
or substitutes for the required human decision.

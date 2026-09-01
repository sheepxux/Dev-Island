# GitHub Repository Controls

Dev Island's CI and Release workflows are repository code. They do not protect
`main` merely by existing: GitHub must require the quality job before merge and
must constrain which Actions the workflows may execute.

## Required commercial-release policy

Before a production release is accepted, `sheepxux/Dev-Island` must satisfy all
of these controls:

### Main branch

- require the `Tests, security, universal build` check;
- require the branch to be current before merging;
- require at least one approving review;
- dismiss stale approvals after new commits;
- require approval of the most recent push by someone other than its author;
- enforce the policy for administrators;
- require every review conversation to be resolved;
- require linear history; and
- prohibit force pushes and branch deletion.

The status check cannot be selected in GitHub until the new CI workflow has
run successfully at least once. Push the reviewed workflow first, observe one
green run, and only then configure the required check. Until that sequence is
complete, PR CI is implemented but is not an enforced merge boundary.

### GitHub Actions

- enable Actions but select **Allow select actions and reusable workflows**;
- allow GitHub-owned Actions;
- do not allow every verified Marketplace publisher;
- allow only the reviewed external action at its exact commit:
  `softprops/action-gh-release@efb35369e0ad2afab669f228072c1b0d510eae64`;
- require Actions to be pinned to a full commit SHA;
- keep the default workflow token permission at read-only; and
- prohibit workflows from approving pull requests.

The workflow declares its exceptional Release permissions explicitly. A broad
default token is therefore unnecessary.

The checked-in Release workflow separately fixes both build-provenance and SBOM
steps to the same GitHub-owned Node 24 action,
`actions/attest@1e69f48acb82d1966a394da916b4c1698aa569d6`
(`v4.2.2`). With only `subject-path`, it emits SLSA build provenance; with the
existing `subject-path` plus `sbom-path`, it emits the SPDX SBOM attestation.
This replaces the older `attest-build-provenance` and now-deprecated
`attest-sbom` wrappers without widening inputs or permissions. Release
publication uses the reviewed Node 24 `softprops/action-gh-release` commit
listed above. GitHub-hosted `macos-15` satisfies the Node 24 Actions runner
minimum; a future self-hosted runner would need version 2.327.1 or newer.

The tag Release checkout also uses `persist-credentials: false`. A dedicated
safe-YAML validator is the first repository command and runs before dependency
resolution or SwiftPM manifest evaluation. It requires that the only explicit
`GITHUB_TOKEN` exposure is scoped to the final pinned GitHub Release action,
after asset verification and attestations. Attack fixtures cover missing or
enabled persistence, checkout token override, early token environment,
missing publication token, and a symlinked workflow.
The fixtures also reject an early GitHub PAT hidden behind a differently named
secret/environment entry.

Both checked-in workflows also pass a separate descriptor-backed run-shell
validator. Before safe loading can collapse ambiguous mappings, it traverses a
bounded Psych AST and requires exactly one document, scalar untagged keys, no
aliases, and no literal or resolved duplicate keys (including `on` / `true`).
It then parses safe YAML, extracts every `run` step, substitutes complete
GitHub expressions with a fixed inert token, and runs `/bin/bash -n` without
executing repository code or reading credentials. PR CI and the tagged Release
both check `ci.yml` and `release.yml` before dependency resolution; the tag
path also does so before credential loading. Fixtures reject unterminated Bash blocks/quotes, non-string scripts,
unreviewed shells, incomplete expressions, literal/resolved duplicate keys,
multiple documents, non-scalar keys, writable files, hard links and symbolic
links. Descriptor stability includes `mtime` and `ctime`; AST traversal is
bounded to 20,000 nodes and 128 levels. This is a static syntax boundary, not
proof that commands will succeed on a real runner.

The validator resolves the effective shell using GitHub precedence: step,
job-level `defaults.run.shell`, workflow-level `defaults.run.shell`, then the
macOS Bash default. Every explicitly declared default is validated even when a
step overrides it. Only exact `bash` and `/bin/bash` are reviewed; arguments,
expressions, whitespace variants, and custom templates such as `bash -c ...`
or `bash {0}` are rejected because they can place runner commands outside the
checked `run` body.

After both workflow files pass, the same first CI/release gate validates the
complete repository script closure before dependency resolution; the tag path
also does so before credential loading. A descriptor-backed walker currently
collects all 50 Bash, 23 Ruby, and 6 Swift files under `scripts/`, rejects linked,
writable, unowned, oversized or unstable inputs, then feeds the frozen bytes
through minimal-environment `/bin/bash -n`, `/usr/bin/ruby -c`, or
`/usr/bin/swiftc -parse -` stdin. Bash/Ruby require executable bits; Swift is
invoked through `swift file.swift` and therefore does not. No repository script
is executed. This closes Bash's real partial-execution
behavior where commands before a later parse error can otherwise run first.

GitHub's macOS runner image does not guarantee that `ripgrep` is preinstalled,
while the reviewed repository gates deliberately use `rg` for fixed-string and
bounded source checks. CI and tagged Release therefore test for `rg` and, only
when it is absent, install the runner's Homebrew `ripgrep` formula with Homebrew
auto-update disabled. They print the resolved tool version and complete this
bootstrap before executing any repository-owned gate. The release-foundation
fixtures bind the bootstrap shape and ordering so a runner-image change fails
at the tool boundary instead of silently skipping later security checks.

Before a tag can import the Developer ID certificate, the credential preflight
also proves that the configured Sparkle private key can sign a fixed repository
payload and that the configured public key verifies it. Before publication, the
eight-asset offline gate extracts `SUPublicEDKey` from the App inside the
versioned ZIP and independently verifies the complete archive signature and
Sparkle's exact signed-feed prefix with CryptoKit. A well-formed but mismatched
key, an unrelated 64-byte signature, or signed-byte drift therefore cannot pass
by satisfying only metadata and Base64 shape checks.

The aggregate Security gate now also executes the Codex live-decision
classifier/package attack suite. It keeps interactive island denial distinct
from native timeout fallback, sandbox rejection, and interrupted attempts;
only `explicit_island_deny` may produce an accepted synthetic package. No
checked-in live-decision receipt was required until a real unlocked island Deny
passed the same gate. That real package is now represented by the redacted
`docs/CODEX_LIVE_DECISION_RECEIPT.txt`; CI validates the receipt but does not
convert one dirty-worktree QA session into a clean product or Release claim.

This local workflow boundary does not replace the remote controls above. A
person who can push an arbitrary tag containing a changed workflow can also
change its validators, so branch/tag/release permissions and reviewed Actions
policy remain independent commercial-release requirements.

### Repository security

- keep secret scanning enabled;
- keep secret-scanning push protection enabled; and
- enable Dependabot security updates.

`.github/dependabot.yml` separately opens bounded, grouped weekly update PRs
for SwiftPM and GitHub Actions. The file does not enable the repository-level
Dependabot security-update switch; an administrator must enable that setting.

## Read-only acceptance check

From an authenticated owner/admin checkout:

```sh
./scripts/qa/audit-github-repository-controls.sh
```

The auditor makes only GitHub API `GET` requests. It downloads bounded JSON
snapshots into a temporary directory and passes them to the same offline
validator covered by CI fixtures. It never edits branch protection, Actions
permissions, repository settings, secrets, workflows, tags, or Releases.

Expected accepted output:

```text
GitHub repository controls: PASS
```

Any finding is a release blocker. Do not weaken the validator merely to match
the current remote state; change the reviewed GitHub settings and rerun it.

If GitHub cannot be read, the auditor stops before validation and emits exactly
one bounded classification for that endpoint: network unavailable,
authentication required, repository-administration read access required, rate
limited, or unexpected API failure. It does not echo `gh` stderr because that
text can contain request URLs, account details, or upstream response content.
A transport, authentication, permission, or rate-limit failure is therefore not
misreported as a repository-control finding.

The offline gate runs a fake-`gh` matrix for success, connection reset, HTTP
401/403/404, rate limiting, and unknown failure. Each failure injects private
sentinel text and fails the gate if any raw diagnostic reaches stdout/stderr.
Both PR CI and the tag Release run this gate through the shared security
invariants before the checked-in auditor can be treated as release evidence.

Within one checkout, the shared authoritative-test wrapper now holds a
non-waiting BSD descriptor lock across the full suite and all 65 stability
repetitions. A concurrent local or diagnostic reproduction exits before Swift
instead of contending for the same SwiftPM database. Separate hosted runners
retain their independent checkouts and locks.

## Recovery

If a required check is unavailable because GitHub Actions itself is degraded,
do not disable protection as an undocumented shortcut. Record the incident,
review any temporary policy change, restore the complete policy after the
service recovers, and preserve the before/after audit output with the Release
evidence.

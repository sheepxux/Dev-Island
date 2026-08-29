# homebrew-dev-island (draft)

> **This is a draft of the Cask formula tap, kept in the Dev Island
> monorepo as the source of truth.** The actual public tap lives in a
> separate repo (`sheepxux/homebrew-dev-island`) so users can run
> `brew tap sheepxux/dev-island && brew install --cask dev-island`.

## Publishing flow

1. **Cut a release tag in the Dev Island monorepo** (`git tag v0.3.0 && git push origin v0.3.0`).
2. **GitHub Actions** (`.github/workflows/release.yml`) builds, signs,
   notarizes, staples, and uploads both `Dev-Island.zip` (stable filename)
   and `Dev-Island-0.3.0.zip` (versioned archive) to a GitHub Release. The
   job also attaches `dev-island.rb`, rendered from the exact release version
   and `Dev-Island.zip` SHA-256.
3. **Review and update the tap**: compare the attached `dev-island.rb` with
   the source template, run the local checks below, then copy it into the
   public `homebrew-dev-island` repo and commit/push there.
4. Users `brew update` (automatic on next `brew install` invocation),
   then `brew install --cask dev-island` pulls the new `Dev-Island.zip`.

## Initial tap-repo setup

```sh
# On GitHub, create empty repo: sheepxux/homebrew-dev-island
# Then locally:
mkdir homebrew-dev-island && cd homebrew-dev-island
git init
mkdir Casks
cp /path/to/Dev-Island/dist/homebrew-island/Casks/dev-island.rb Casks/
git add Casks
git commit -m "Initial cask"
git remote add origin git@github.com:sheepxux/homebrew-dev-island.git
git push -u origin main
```

Users then:

```sh
brew tap sheepxux/dev-island
brew install --cask dev-island
```

## Local Cask development

```sh
# From inside the Dev Island monorepo:
./scripts/ci/verify-homebrew-distribution.sh

# After the public tap is published, test the real install lifecycle:
brew tap sheepxux/dev-island
brew install --cask dev-island
brew uninstall --zap --cask dev-island
```

Modern Homebrew rejects standalone Cask paths for `style`. The repository
verifier creates an isolated temporary tap, renders the release-pinned Cask,
runs real `brew style --cask` and `brew readall`, then untaps it. It also
checks the version/URL/SHA, Bundle ID, macOS floor, zap paths, deterministic
rendering, and the absence of install-time scripts or `sha256 :no_check`.

`--zap` removes Dev Island preferences, cache, saved state, and the real
`~/Library/Application Support/island-app` SQLite directory. It intentionally
does not delete Keychain entries. Disconnect Manus inside Dev Island before
uninstalling if the API key should also be removed.

The current release is secure polling-only, so the Cask does not install
`cloudflared`. Realtime must remain disabled until the Manus signature trust
anchor is verified and the data-flow/security review is updated.

## Audit-readiness checklist (before submitting to homebrew/cask main repo)

The Homebrew Cask main repo has a higher bar than personal taps. If you
ever want Dev Island in the canonical `brew install --cask dev-island`
namespace (no tap required), the formula needs:

- [x] Notarized .app (already done by the release workflow)
- [x] `sha256` pinned to a specific release (no `:latest`)
- [x] `zap` stanza for clean uninstall
- [ ] `livecheck` block for auto-update detection
- [ ] At least one stable release published for ~30 days
- [ ] No bundled binaries for things already in Homebrew (✓ — we depend
      on the cloudflared Cask rather than bundling it)

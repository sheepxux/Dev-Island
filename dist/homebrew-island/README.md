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
   job log prints `Dev-Island.zip`'s SHA-256.
3. **Update the tap**: in the public `homebrew-dev-island` repo, edit
   `Casks/dev-island.rb`:
   - bump `version`
   - paste the new `sha256` from the release log
   - commit, push
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
brew install --cask ./dist/homebrew-island/Casks/dev-island.rb

# Validate formula style:
brew style ./dist/homebrew-island/Casks/dev-island.rb

# Test full lifecycle:
brew uninstall --zap --cask dev-island
```

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

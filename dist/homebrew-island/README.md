# homebrew-island (draft)

> **This is a draft of the Cask formula tap, kept in the Island monorepo
> as the source of truth.** The actual public tap lives in a separate
> repo (`<your-handle>/homebrew-island`) so users can run
> `brew tap <your-handle>/island && brew install --cask island`.

## Publishing flow

1. **Cut a release tag in the Island monorepo** (`git tag v0.1.0 && git push origin v0.1.0`).
2. **GitHub Actions** (`.github/workflows/release.yml`) builds, signs,
   notarizes, staples, and uploads `Island-0.1.0.zip` to a GitHub
   Release. The job log prints the artifact's SHA-256.
3. **Update the tap**: in the public `homebrew-island` repo, edit
   `Casks/island.rb`:
   - bump `version`
   - paste the new `sha256` from the release log
   - commit, push
4. Users `brew update` (automatic on next `brew install` invocation),
   then `brew install --cask island` pulls the new `.zip`.

## Initial tap-repo setup

```sh
# On GitHub, create empty repo: <your-handle>/homebrew-island
# Then locally:
mkdir homebrew-island && cd homebrew-island
git init
mkdir Casks
cp /path/to/Island/dist/homebrew-island/Casks/island.rb Casks/
git add Casks
git commit -m "Initial cask"
git remote add origin git@github.com:<your-handle>/homebrew-island.git
git push -u origin main
```

Users then:

```sh
brew tap <your-handle>/island
brew install --cask island
```

## Local Cask development

```sh
# From inside the Island monorepo:
brew install --cask ./dist/homebrew-island/Casks/island.rb

# Validate formula style:
brew style ./dist/homebrew-island/Casks/island.rb

# Test full lifecycle:
brew uninstall --zap --cask island
```

## Audit-readiness checklist (before submitting to homebrew/cask main repo)

The Homebrew Cask main repo has a higher bar than personal taps. If you
ever want Island in the canonical `brew install --cask island` namespace
(no tap required), the formula needs:

- [x] Notarized .app (already done by the release workflow)
- [x] `sha256` pinned to a specific release (no `:latest`)
- [x] `zap` stanza for clean uninstall
- [ ] `livecheck` block for auto-update detection
- [ ] At least one stable release published for ~30 days
- [ ] No bundled binaries for things already in Homebrew (✓ — we depend
      on the cloudflared Cask rather than bundling it)

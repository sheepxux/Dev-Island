# frozen_string_literal: true

# Dev Island — A live status bar for the AI agents working in the
# background.
#
# This Cask is meant to live in a separate `sheepxux/homebrew-dev-island`
# tap repo, NOT inside the Dev Island monorepo itself. We keep this draft
# under `dist/homebrew-island/Casks/dev-island.rb` so the source-of-truth
# stays version-controlled alongside the app, but the actual brew tap
# repository pulls (or copies) this file at release time.
#
# Quick local test (before publishing the tap):
#   brew install --cask ./dist/homebrew-island/Casks/dev-island.rb
#
# Why no `livecheck` block: livecheck auto-opens issues when version
# detection breaks, and we publish releases manually for now. Add it
# once we have a stable cadence:
#
#   livecheck do
#     url :url
#     strategy :github_latest
#   end
cask "dev-island" do
  version "0.1.1"
  # Replaced by the GitHub Actions release workflow's per-tag SHA-256
  # before publishing. Local test value is the SHA of the most recent
  # local build under build/Island.zip.
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  # Stable filename — `Island.zip` is also published as a per-version
  # asset (`Island-#{version}.zip`) but pinning to the stable name lets
  # the cask formula update with just the SHA, not the URL.
  url "https://github.com/sheepxux/Dev-Island/releases/download/v#{version}/Island.zip"
  name "Dev Island"
  desc "Live status bar for AI agents working in the background"
  homepage "https://devisland.app"

  # Apple Silicon arm64 + Intel x86_64 universal binary. macOS 14+ for
  # the SwiftUI / Observation features Dev Island uses.
  depends_on macos: ">= :sonoma"

  # Realtime task updates rely on a cloudflared tunnel exposing a local
  # webhook receiver to Manus. Without cloudflared the app still works
  # via 60-second polling — see CloudflaredProcess.swift findCloudflaredBinary
  # for the resolution order — so this is a soft preference, not a
  # functional requirement.
  #
  # We use `depends_on cask:` rather than `depends_on formula:` because
  # cloudflared ships as a Cask in homebrew-cask, not a formula.
  depends_on cask: "cloudflared"

  app "Island.app"

  # `zap` is what `brew uninstall --zap dev-island` uses to wipe per-user
  # state. Listing every location Dev Island writes to means a clean
  # uninstall doesn't leave behind:
  # - the SQLite store from IslandCore.SQLiteStore
  # - app preferences from `defaults` (UserDefaults suite name matches
  #   the bundle identifier app.devisland.Island)
  # - Saved Application State frame data
  #
  # The Keychain entry that holds the Manus API key is handled by macOS
  # itself when the bundle is removed, no `zap` entry needed.
  zap trash: [
    "~/Library/Application Support/Dev Island",
    "~/Library/Preferences/app.devisland.Island.plist",
    "~/Library/Caches/app.devisland.Island",
    "~/Library/Saved Application State/app.devisland.Island.savedState",
  ]
end

# frozen_string_literal: true

# Island.app — Dynamic-Island-style menubar status for Manus AI tasks.
#
# This Cask is meant to live in a separate `sheepxux/homebrew-island`
# tap repo, NOT inside the Island monorepo itself. We keep this draft
# under `dist/homebrew-island/Casks/island.rb` so the source-of-truth
# stays version-controlled alongside the app, but the actual brew tap
# repository pulls (or copies) this file at release time.
#
# Quick local test (before publishing the tap):
#   brew install --cask ./dist/homebrew-island/Casks/island.rb
#
# Why no `livecheck` block: livecheck auto-opens issues when version
# detection breaks, and we publish releases manually for now. Add it
# once we have a stable cadence:
#
#   livecheck do
#     url :url
#     strategy :github_latest
#   end
cask "island" do
  version "0.1.0"
  # Replaced by the GitHub Actions release workflow's per-tag SHA-256
  # before publishing. Local test value is the SHA of the most recent
  # local build under build/Island-<version>.zip.
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/sheepxux/Dev-Island/releases/download/v#{version}/Island-#{version}.zip"
  name "Island"
  desc "Dynamic-Island-style menubar status for Manus AI tasks"
  homepage "https://devisland.app"

  # Apple Silicon arm64 + Intel x86_64 universal binary. macOS 14+ for
  # the SwiftUI / Observation features Island uses.
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

  # `zap` is what `brew uninstall --zap island` uses to wipe per-user
  # state. Listing every location Island writes to means a clean
  # uninstall doesn't leave behind:
  # - the SQLite store from IslandCore.SQLiteStore
  # - the Keychain entry written by IslandCore.KeychainStore (handled
  #   by macOS, not files — no zap entry)
  # - app preferences from `defaults`
  # - log files from os.Logger (handled by the system log subsystem,
  #   not files we own — no zap entry)
  zap trash: [
    "~/Library/Application Support/Island",
    "~/Library/Preferences/com.island.app.plist",
    "~/Library/Caches/com.island.app",
    "~/Library/Saved Application State/com.island.app.savedState",
  ]
end

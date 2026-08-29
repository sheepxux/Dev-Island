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
# Quick local validation (before publishing the tap):
#   ./scripts/ci/verify-homebrew-distribution.sh
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
  version "0.3.0"
  # SHA-256 of the notarized stable-name ZIP attached to the v0.3.0 release.
  sha256 "8271a3cd171f3b04b78eda23451e94a77b9284f314f1b8b8d17850376acf913c"

  # Stable filename — `Dev-Island.zip` is also published as a per-version
  # asset (`Dev-Island-#{version}.zip`) but pinning to the stable name
  # lets the cask formula update with just the SHA, not the URL.
  url "https://github.com/sheepxux/Dev-Island/releases/download/v#{version}/Dev-Island.zip"
  name "Dev Island"
  desc "Live status bar for AI agents working in the background"
  homepage "https://devisland.app/"

  # Apple Silicon arm64 + Intel x86_64 universal binary. macOS 14+ for
  # the SwiftUI / Observation features Dev Island uses.
  depends_on macos: :sonoma

  app "Dev Island.app"

  uninstall quit: "app.devisland.Island"

  # `zap` is what `brew uninstall --zap dev-island` uses to wipe per-user
  # state. Listing every location Dev Island writes to means a clean
  # uninstall doesn't leave behind:
  # - the SQLite store from IslandCore.SQLiteStore
  # - app preferences from `defaults` (UserDefaults suite name matches
  #   the bundle identifier app.devisland.Island)
  # - Saved Application State frame data
  #
  # Homebrew must not delete a generic-password Keychain item through a zap
  # stanza. Users who want it removed should Disconnect Manus in the app
  # before uninstalling; deleting an app does not delete its Keychain items.
  zap trash: [
    "~/Library/Application Support/island-app",
    "~/Library/Caches/app.devisland.Island",
    "~/Library/Preferences/app.devisland.Island.plist",
    "~/Library/Saved Application State/app.devisland.Island.savedState",
  ]
end

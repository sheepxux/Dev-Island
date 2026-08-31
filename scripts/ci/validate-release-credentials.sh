#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SPARKLE_SIGN_TOOL="$ROOT/.build/artifacts/sparkle/Sparkle/bin/sign_update"
SPARKLE_SIGNATURE_VERIFIER="$ROOT/scripts/release/verify-sparkle-ed25519-signatures.swift"
KEY_PAIR_PAYLOAD="$ROOT/VERSION"

fail() {
  echo "::error::$1" >&2
  exit 1
}

is_canonical_base64() {
  local raw_value="$1"
  local value
  local round_trip
  if printf '%s' "$raw_value" | LC_ALL=C grep -q '[^A-Za-z0-9+/=[:space:]]'; then
    return 1
  fi
  value="$(printf '%s' "$raw_value" | tr -d '[:space:]')"
  [[ "$value" =~ ^[A-Za-z0-9+/]+={0,2}$ ]] || return 1
  (( ${#value} % 4 == 0 )) || return 1
  round_trip="$(
    printf '%s' "$value" \
      | base64 --decode \
      | base64 \
      | tr -d '\n'
  )" || return 1
  [[ "$round_trip" == "$value" ]]
}

# This validator checks only presence and non-secret structure. It must never
# print a credential value, decoded key, certificate, or password.
for variable in \
  APPLE_ID \
  APPLE_TEAM_ID \
  APPLE_APP_PASSWORD \
  P12_BASE64 \
  P12_PASSWORD \
  KEYCHAIN_PASSWORD \
  SPARKLE_PUBLIC_ED_KEY \
  SPARKLE_PRIVATE_ED_KEY; do
  if [[ -z "${!variable:-}" ]]; then
    fail "Required release credential is missing: ${variable}"
  fi
done

[[ "${APPLE_ID}" == *@* ]] \
  || fail "APPLE_ID must be an email address"
[[ "${APPLE_TEAM_ID}" =~ ^[A-Z0-9]{10}$ ]] \
  || fail "APPLE_TEAM_ID must be a 10-character Apple Team ID"
[[ ${#KEYCHAIN_PASSWORD} -ge 20 ]] \
  || fail "KEYCHAIN_PASSWORD must contain at least 20 characters"

# Sparkle's Ed25519 public key is exactly 32 decoded bytes. Validate it
# without writing either update key to disk.
is_canonical_base64 "${SPARKLE_PUBLIC_ED_KEY}" \
  || fail "SPARKLE_PUBLIC_ED_KEY must be valid canonical base64"
if ! public_key_bytes="$(
  printf '%s' "${SPARKLE_PUBLIC_ED_KEY}" \
    | tr -d '[:space:]' \
    | base64 --decode \
    | wc -c \
    | tr -d '[:space:]'
)"; then
  fail "SPARKLE_PUBLIC_ED_KEY must be valid base64"
fi
[[ "${public_key_bytes}" == "32" ]] \
  || fail "SPARKLE_PUBLIC_ED_KEY must decode to exactly 32 bytes"

# Reject malformed PKCS#12 base64 before touching a keychain. The decoded
# bytes travel only through the pipe and are discarded immediately.
is_canonical_base64 "${P12_BASE64}" \
  || fail "SIGNING_CERTIFICATE_P12_BASE64 must be valid base64"

# Shape alone is not a trust chain: a well-formed public key can still be
# unrelated to the private key used by generate_appcast. Sign one fixed public
# repository payload through Sparkle's stdin-only key channel, then verify the
# result with CryptoKit and the exact configured public key. Neither key is
# written, printed, or inherited by either child process.
[[ -f "$SPARKLE_SIGN_TOOL" && ! -L "$SPARKLE_SIGN_TOOL" && -x "$SPARKLE_SIGN_TOOL" ]] \
  || fail "Pinned Sparkle signing tool is unavailable"
[[ -f "$SPARKLE_SIGNATURE_VERIFIER" && ! -L "$SPARKLE_SIGNATURE_VERIFIER" ]] \
  || fail "Repository Ed25519 verifier is unavailable"
[[ -f "$KEY_PAIR_PAYLOAD" && ! -L "$KEY_PAIR_PAYLOAD" ]] \
  || fail "Release key-pair challenge payload is unavailable"

sparkle_public_key="$(
  printf '%s' "${SPARKLE_PUBLIC_ED_KEY}" | tr -d '[:space:]'
)"
sparkle_private_key="${SPARKLE_PRIVATE_ED_KEY}"
unset SPARKLE_PRIVATE_ED_KEY

clear_key_material() {
  sparkle_public_key=""
  sparkle_private_key=""
  unset sparkle_public_key sparkle_private_key
}
trap clear_key_material EXIT INT TERM

if ! key_pair_signature="$(
  printf '%s' "$sparkle_private_key" \
    | env -i \
        PATH='/usr/bin:/bin' \
        LANG='C' \
        LC_ALL='C' \
        "$SPARKLE_SIGN_TOOL" \
          --ed-key-file - \
          -p \
          "$KEY_PAIR_PAYLOAD" \
          2>/dev/null
)"; then
  fail "SPARKLE_PRIVATE_ED_KEY could not sign the release key-pair challenge"
fi

if ! env -i \
  PATH='/usr/bin:/bin' \
  LANG='C' \
  LC_ALL='C' \
  /usr/bin/swift \
    "$SPARKLE_SIGNATURE_VERIFIER" \
    verify-file \
    --public-key-base64 "$sparkle_public_key" \
    --signature-base64 "$key_pair_signature" \
    --input-file "$KEY_PAIR_PAYLOAD" \
    >/dev/null 2>&1; then
  fail "SPARKLE_PUBLIC_ED_KEY and SPARKLE_PRIVATE_ED_KEY must form one Ed25519 key pair"
fi
key_pair_signature=""
unset key_pair_signature

echo "Release credential trust chain: PASS"

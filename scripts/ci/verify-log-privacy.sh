#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fail() {
  echo "::error::$1" >&2
  exit 1
}

SOURCE_ROOTS=(
  IslandApp
  IslandAppLib
  IslandCore/Sources
)

# Every unified-log channel is declared in one of two reviewed registries.
# Ad-hoc Logger construction would otherwise bypass the call-site checks below.
while IFS= read -r logger_file; do
  case "$logger_file" in
    IslandCore/Sources/IslandCore/Internal/Logger.swift|IslandAppLib/Support/AppLogger.swift)
      ;;
    *)
      fail "Ad-hoc Logger construction must move to a reviewed registry: $logger_file"
      ;;
  esac
done < <(rg -l '\bLogger\(' "${SOURCE_ROOTS[@]}" --glob '*.swift')

# Raw Error descriptions can carry provider text, paths, URLs, SQL details,
# or identifiers. Runtime logs must use the operation context as the bounded
# category instead of serializing arbitrary Error values.
if rg -n '\\\((error|err)\)' "${SOURCE_ROOTS[@]}" --glob '*.swift'; then
  fail "Production runtime code must not interpolate raw Error descriptions"
fi
if rg -n 'String\(describing: (cfError|[^)]*error)' "${SOURCE_ROOTS[@]}" --glob '*.swift'; then
  fail "Production runtime code must not stringify low-level errors"
fi

# Known high-cardinality values must never cross into unified logging. These
# checks intentionally inspect Logger call sites rather than banning the same
# values from the network/storage implementation that legitimately needs them.
if rg -n '(IslandLogger\.[A-Za-z]+|AppLogger\.[A-Za-z]+)\.[A-Za-z]+\([^\n]*(request\.url|absoluteString|task\.id|event\.taskId|payload\.taskId|webhookId|url\.path|processIdentifier|key, privacy|localizedDescription)' \
  "${SOURCE_ROOTS[@]}" --glob '*.swift'; then
  fail "Unified logging contains an ID, URL, path, process ID, or key value"
fi
for forbidden_copy in \
  'Tunnel URL:' \
  'Webhook registered:' \
  'Webhook deleted:' \
  'SQLite opened at' \
  'cloudflared:' \
  'taskId='; do
  if rg -n -F "$forbidden_copy" "${SOURCE_ROOTS[@]}" --glob '*.swift'; then
    fail "High-cardinality runtime log copy was reintroduced: $forbidden_copy"
  fi
done

if rg -n '\b(print|debugPrint|dump)\(' "${SOURCE_ROOTS[@]}" --glob '*.swift'; then
  fail "Shipping app/runtime sources must not emit ad-hoc stdout diagnostics"
fi

if rg -n 'as! HTTPURLResponse' IslandCore/Sources --glob '*.swift'; then
  fail "HTTP transport responses must be validated without a forced cast"
fi

MANUS_TESTS="IslandCoreTests/Sources/IslandCoreTests/ManusAPIClientTests.swift"
PRESENTATION_TESTS="IslandAppLibTests/Sources/IslandAppLibTests/ManusConnectionErrorPresentationTests.swift"
for regression in \
  testNonHTTPResponseFailsClosedForDecodingEndpoint \
  testNonHTTPResponseFailsClosedForVoidEndpoint; do
  rg -q "$regression" "$MANUS_TESTS" \
    || fail "Manus transport crash-safety regression missing: $regression"
done
rg -q 'testProviderAndUnknownErrorDetailsAreNeverReflected' "$PRESENTATION_TESTS" \
  || fail "Settings must prove provider error details are never reflected"

echo "Runtime log privacy invariants: PASS"

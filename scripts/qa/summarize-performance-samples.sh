#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=C

usage() {
  echo "usage: $0 INPUT_CSV [MAX_AVERAGE_CPU] [MAX_RSS_SLOPE_KB_PER_MINUTE] [MAX_RSS_GROWTH_KB]" >&2
  exit 64
}

[[ $# -ge 1 && $# -le 4 ]] || usage

QA_INPUT_CSV="$1"
QA_MAX_AVERAGE_CPU="${2:-}"
QA_MAX_RSS_SLOPE="${3:-}"
QA_MAX_RSS_GROWTH="${4:-}"

[[ -f "$QA_INPUT_CSV" && ! -L "$QA_INPUT_CSV" ]] \
  || { echo "error: input must be a regular non-symlink CSV" >&2; exit 2; }

for threshold in \
  "$QA_MAX_AVERAGE_CPU" \
  "$QA_MAX_RSS_SLOPE" \
  "$QA_MAX_RSS_GROWTH"; do
  [[ -z "$threshold" || "$threshold" =~ ^[0-9]+([.][0-9]+)?$ ]] || usage
done

[[ "$(sed -n '1p' "$QA_INPUT_CSV")" == \
   "timestamp_utc,elapsed_seconds,cpu_percent,rss_kb" ]] \
  || { echo "error: unexpected performance CSV header" >&2; exit 2; }

# Reject partial, reordered, non-finite, negative, or malformed rows before
# computing statistics. The timestamp is deliberately opaque but must stay a
# single non-empty field; elapsed time is the authoritative ordering axis.
awk -F, '
  NR == 1 { next }
  NF != 4 || $1 == "" || $2 !~ /^[0-9]+([.][0-9]+)?$/ ||
  $3 !~ /^[0-9]+([.][0-9]+)?$/ || $4 !~ /^[0-9]+$/ { exit 1 }
  count > 0 && ($2 + 0) <= previous { exit 1 }
  { previous = $2 + 0; count += 1 }
  END { if (count < 1) exit 1 }
' "$QA_INPUT_CSV" \
  || { echo "error: malformed or non-monotonic performance samples" >&2; exit 2; }

QA_SAMPLE_COUNT="$(awk 'END { print NR - 1 }' "$QA_INPUT_CSV")"
QA_FIRST_ELAPSED="$(awk -F, 'NR == 2 { print $2; exit }' "$QA_INPUT_CSV")"
QA_LAST_ELAPSED="$(awk -F, 'END { print $2 }' "$QA_INPUT_CSV")"
QA_OBSERVATION_SPAN="$(awk -v first="$QA_FIRST_ELAPSED" -v last="$QA_LAST_ELAPSED" \
  'BEGIN { printf "%.3f", last - first }')"

nearest_rank() {
  local column="$1"
  local numerator="$2"
  local denominator="$3"
  local rank
  rank=$(( (numerator * QA_SAMPLE_COUNT + denominator - 1) / denominator ))
  awk -F, -v column="$column" 'NR > 1 { print $column }' "$QA_INPUT_CSV" \
    | sort -n \
    | sed -n "${rank}p"
}

QA_AVG_CPU="$(awk -F, 'NR > 1 { sum += $3; count += 1 } END { printf "%.3f", sum / count }' "$QA_INPUT_CSV")"
QA_P50_CPU="$(nearest_rank 3 50 100 | awk '{ printf "%.3f", $1 }')"
QA_P95_CPU="$(nearest_rank 3 95 100 | awk '{ printf "%.3f", $1 }')"
QA_MAX_CPU="$(awk -F, 'NR > 1 && $3 > max { max = $3 } END { printf "%.3f", max }' "$QA_INPUT_CSV")"

QA_AVG_RSS="$(awk -F, 'NR > 1 { sum += $4; count += 1 } END { printf "%.0f", sum / count }' "$QA_INPUT_CSV")"
QA_P50_RSS="$(nearest_rank 4 50 100 | awk '{ printf "%.0f", $1 }')"
QA_P95_RSS="$(nearest_rank 4 95 100 | awk '{ printf "%.0f", $1 }')"
QA_MAX_RSS="$(awk -F, 'NR > 1 && $4 > max { max = $4 } END { printf "%.0f", max }' "$QA_INPUT_CSV")"
QA_START_RSS="$(awk -F, 'NR == 2 { printf "%.0f", $4; exit }' "$QA_INPUT_CSV")"
QA_END_RSS="$(awk -F, 'END { printf "%.0f", $4 }' "$QA_INPUT_CSV")"
QA_RSS_GROWTH="$(awk -v start="$QA_START_RSS" -v end="$QA_END_RSS" \
  'BEGIN { printf "%.0f", end - start }')"
QA_RSS_SLOPE="$(awk -F, '
  NR > 1 {
    count += 1
    x = $2 + 0
    y = $4 + 0
    sum_x += x
    sum_y += y
    sum_xx += x * x
    sum_xy += x * y
  }
  END {
    denominator = count * sum_xx - sum_x * sum_x
    if (count < 2 || denominator == 0) {
      printf "0.000"
    } else {
      printf "%.3f", ((count * sum_xy - sum_x * sum_y) / denominator) * 60
    }
  }
' "$QA_INPUT_CSV")"

printf 'sample_count=%s\n' "$QA_SAMPLE_COUNT"
printf 'observation_span_seconds=%s\n' "$QA_OBSERVATION_SPAN"
printf 'average_cpu_percent=%s\n' "$QA_AVG_CPU"
printf 'p50_cpu_percent=%s\n' "$QA_P50_CPU"
printf 'p95_cpu_percent=%s\n' "$QA_P95_CPU"
printf 'maximum_cpu_percent=%s\n' "$QA_MAX_CPU"
printf 'average_rss_kb=%s\n' "$QA_AVG_RSS"
printf 'p50_rss_kb=%s\n' "$QA_P50_RSS"
printf 'p95_rss_kb=%s\n' "$QA_P95_RSS"
printf 'maximum_rss_kb=%s\n' "$QA_MAX_RSS"
printf 'starting_rss_kb=%s\n' "$QA_START_RSS"
printf 'ending_rss_kb=%s\n' "$QA_END_RSS"
printf 'rss_growth_kb=%s\n' "$QA_RSS_GROWTH"
printf 'rss_slope_kb_per_minute=%s\n' "$QA_RSS_SLOPE"

if [[ -n "$QA_MAX_AVERAGE_CPU" ]]; then
  awk -v actual="$QA_AVG_CPU" -v limit="$QA_MAX_AVERAGE_CPU" \
    'BEGIN { exit !(actual <= limit) }' \
    || { echo "error: average CPU $QA_AVG_CPU exceeds limit $QA_MAX_AVERAGE_CPU" >&2; exit 4; }
fi
if [[ -n "$QA_MAX_RSS_SLOPE" ]]; then
  awk -v actual="$QA_RSS_SLOPE" -v limit="$QA_MAX_RSS_SLOPE" \
    'BEGIN { exit !(actual <= limit) }' \
    || { echo "error: RSS slope $QA_RSS_SLOPE KB/min exceeds limit $QA_MAX_RSS_SLOPE" >&2; exit 4; }
fi
if [[ -n "$QA_MAX_RSS_GROWTH" ]]; then
  awk -v actual="$QA_RSS_GROWTH" -v limit="$QA_MAX_RSS_GROWTH" \
    'BEGIN { exit !(actual <= limit) }' \
    || { echo "error: RSS growth $QA_RSS_GROWTH KB exceeds limit $QA_MAX_RSS_GROWTH" >&2; exit 4; }
fi

#!/usr/bin/env bash
# Asserts how many actions a Bazel build executed, served from the action cache, and served from the disk cache.
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "usage: $0 <build-log> <executed> <action-cache-hits> <disk-cache-hits>" >&2
  exit 2
fi

log="$1" want_executed="$2" want_action_hits="$3" want_disk_hits="$4"
executed=0 action_hits=0 disk_hits=0

summary="$(grep -E '^INFO: [0-9]+ process(es)?:' "${log}" | tail -1)"
[[ -n "${summary}" ]] || { echo "FAIL: no process summary found in ${log}"; exit 1; }
echo "${summary}"

# Strips the "INFO: N processes: " prefix and the trailing period, then tallies each category.
while IFS= read -r entry; do
  count="${entry%% *}"
  label="${entry#* }"
  case "${label}" in
    internal) ;;
    "action cache hit") action_hits=$((action_hits + count)) ;;
    "disk cache hit") disk_hits=$((disk_hits + count)) ;;
    *) executed=$((executed + count)) ;;
  esac
done < <(echo "${summary}" | sed -E 's/^INFO: [0-9]+ process(es)?: //; s/\.$//' | tr ',' '\n' | sed -E 's/^ +//')

echo "executed=${executed} action_cache_hits=${action_hits} disk_cache_hits=${disk_hits}"
if [[ "${executed}" != "${want_executed}" || "${action_hits}" != "${want_action_hits}" || "${disk_hits}" != "${want_disk_hits}" ]]; then
  echo "FAIL: expected executed=${want_executed} action_cache_hits=${want_action_hits} disk_cache_hits=${want_disk_hits}"
  exit 1
fi
echo "PASS"

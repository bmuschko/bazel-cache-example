#!/usr/bin/env bash
# Demonstrates Bazel's in-memory, local action cache, and on-disk caching layers.
set -euo pipefail

cd "$(dirname "$0")/.."

BAZEL="${BAZEL:-bazelisk}"
TARGET="//:report"
DISK_CACHE_DIR="${HOME}/.cache/bazel-cache-example/disk-cache"

# Builds the target and asserts how many actions ran, hit the action cache, and hit the disk cache.
build_and_check() {
  local title="$1" want_executed="$2" want_action_hits="$3" want_disk_hits="$4"
  local log summary executed=0 action_hits=0 disk_hits=0 count label start end

  echo
  echo "=== ${title}"
  log="$(mktemp)"
  start=$(date +%s)
  "${BAZEL}" build --config=disk "${TARGET}" 2>&1 | tee "${log}"
  end=$(date +%s)

  summary="$(grep -E '^INFO: [0-9]+ process(es)?:' "${log}" | tail -1)"
  rm -f "${log}"
  [[ -n "${summary}" ]] || { echo "FAIL: no process summary found"; exit 1; }

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

  echo "--> executed=${executed} action_cache_hits=${action_hits} disk_cache_hits=${disk_hits} wall_time=$((end - start))s"
  if [[ "${executed}" != "${want_executed}" || "${action_hits}" != "${want_action_hits}" || "${disk_hits}" != "${want_disk_hits}" ]]; then
    echo "FAIL: expected executed=${want_executed} action_cache_hits=${want_action_hits} disk_cache_hits=${want_disk_hits}"
    exit 1
  fi
  echo "PASS"
}

full_demo() {
  local greeting_file="data/greeting.txt"
  local original_greeting
  original_greeting="$(cat "${greeting_file}")"
  trap 'printf "%s\n" "${original_greeting}" > "${greeting_file}"' EXIT

  "${BAZEL}" clean --expunge
  rm -rf "${DISK_CACHE_DIR}"

  build_and_check "1. Cold build: every action executes" 3 0 0
  build_and_check "2. Rebuild in the same server: the in-memory graph skips all actions" 0 0 0

  "${BAZEL}" shutdown
  build_and_check "3. Rebuild after server restart: the action cache in the output base is reused" 0 3 0

  "${BAZEL}" clean --expunge
  build_and_check "4. Rebuild after clean --expunge: outputs come from the on-disk cache" 0 0 3

  printf 'Howdy\n' > "${greeting_file}"
  build_and_check "5. Change one input: only dependent actions execute" 2 0 0

  printf "%s\n" "${original_greeting}" > "${greeting_file}"
  build_and_check "6. Revert the change: the previous outputs come from the on-disk cache" 0 0 2
}

case "${1:-full}" in
  full) full_demo ;;
  populate)
    "${BAZEL}" clean --expunge
    rm -rf "${DISK_CACHE_DIR}"
    build_and_check "Populate the on-disk cache" 3 0 0
    ;;
  reuse)
    "${BAZEL}" clean --expunge
    build_and_check "Reuse the on-disk cache restored from another job" 0 0 3
    ;;
  *)
    echo "usage: $0 [full|populate|reuse]" >&2
    exit 2
    ;;
esac

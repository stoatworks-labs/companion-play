#!/usr/bin/env bash
# Shared helpers for the build scripts. Sourced, never run.
#
# The generic half — checksums, loop devices, chroots, Armbian's quirks and the
# pinned base image — lives in `playbase`, shared with weblinked-os and polecat
# so a fix lands once. Only companion-play-specific things belong below.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# playbase is expected as a sibling checkout, matching the rest of the fleet.
PLAYBASE="${PLAYBASE:-$(cd "${REPO_ROOT}/../playbase" 2>/dev/null && pwd || true)}"
if [ -z "$PLAYBASE" ] || [ ! -f "${PLAYBASE}/lib.sh" ]; then
  printf 'xxx playbase not found.\n' >&2
  printf '    Expected a sibling checkout at %s/../playbase\n' "$REPO_ROOT" >&2
  printf '    git clone https://github.com/stoatworks-labs/playbase.git\n' >&2
  printf '    or set PLAYBASE=/path/to/playbase\n' >&2
  exit 1
fi

# shellcheck source=/dev/null
. "${PLAYBASE}/lib.sh"
# shellcheck source=/dev/null
. "${PLAYBASE}/base.conf"
# shellcheck source=./config.sh
. "${REPO_ROOT}/build/config.sh"

WORK="${REPO_ROOT}/${WORK_DIR}"
OUT="${REPO_ROOT}/${OUT_DIR}"
CACHE="${REPO_ROOT}/${CACHE_DIR}"
VENDOR="${REPO_ROOT}/${VENDOR_DIR}"
mkdir -p "$WORK" "$OUT" "$CACHE" "$VENDOR"

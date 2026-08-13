#!/usr/bin/env bash
# Fetch Companion's linux-arm64 tarball and stage the offline module bundle.
#
# Runs on any host — no root, no loop devices, no chroot. Keeping the downloads
# in their own step means an image rebuild does not re-fetch 600 MB, and means
# the two vendor artifacts can be checked *before* a build starts rather than
# failing an hour in.
#
# Nothing here is committed: vendor/ and cache/ are both gitignored. Companion
# is Bitfocus's to distribute, not ours to redistribute.

. "$(dirname "$0")/lib.sh"

need curl tar

# --- Companion tarball -------------------------------------------------------

TGZ="${CACHE}/${COMPANION_TARBALL}"

if [ -f "$TGZ" ]; then
  log "using cached ${COMPANION_TARBALL}"
else
  log "downloading ${COMPANION_TARBALL} (~360 MiB)"
  curl -fSL --retry 3 -o "${TGZ}.part" "$COMPANION_URL"
  mv "${TGZ}.part" "$TGZ"
fi

# TRAP, paid for here: do NOT write these checks as `tar -tzf … | grep -q …`.
# Under `set -o pipefail`, grep -q exits at the first match and closes the pipe,
# tar dies of SIGPIPE, and the pipeline reports failure — so a SUCCESSFUL match
# fails the build. It presents as "the layout changed" on a perfectly good
# download. Listing once into a file also avoids decompressing 360 MB twice.
log "checking tarball layout"
LISTING="${CACHE}/${COMPANION_TARBALL}.listing"
if [ ! -s "$LISTING" ]; then
  # Written aside and moved, so an interrupted listing cannot be mistaken for a
  # complete one on the next run and pass the checks below by omission.
  tar -tzf "$TGZ" > "${LISTING}.part"
  mv "${LISTING}.part" "$LISTING"
fi

# No published checksum to pin against, so assert on the shape instead: the
# install is `--strip-components=2 --wildcards '*/resources'`, and if that
# pattern matches nothing the extract silently produces an empty /opt/companion
# and the image boots into a service that exits immediately.
grep -c '^[^/]*/resources/main\.js$' "$LISTING" >/dev/null \
  || die "no */resources/main.js in ${COMPANION_TARBALL}.
  The tarball layout changed, or the download is truncated. The install in
  03-make-image.sh extracts '*/resources' and would silently produce an empty
  ${CP_INSTALL_DIR}."

# --- Companion's licence text ------------------------------------------------
#
# MIT requires the copyright notice to travel with the software, and an image is
# a distribution. Companion's own LICENSE.md is NOT in the release tarball — it
# lives inside app.asar — so it is fetched from the tag that matches the pinned
# build and installed into the image next to the rest of the notices.
#
# Found the hard way: the first version of this shipped an ATTRIBUTIONS.md
# pointing at a licence file the build never created, because the copy step was
# guarded by an `if [ -f ... ]` on a path that does not exist in the tarball. A
# notice obligation silently satisfied by nothing is worse than none.
COMPANION_LICENCE="${CACHE}/companion-LICENSE-${COMPANION_VERSION}.md"
COMPANION_LICENCE_URL="https://raw.githubusercontent.com/bitfocus/companion/v${COMPANION_VERSION}/LICENSE.md"

if [ -s "$COMPANION_LICENCE" ]; then
  log "using cached Companion licence text"
else
  log "fetching Companion ${COMPANION_VERSION} licence text"
  curl -fSL --retry 3 -o "${COMPANION_LICENCE}.part" "$COMPANION_LICENCE_URL"
  mv "${COMPANION_LICENCE}.part" "$COMPANION_LICENCE"
fi

grep -q 'MIT License' "$COMPANION_LICENCE" \
  || die "${COMPANION_LICENCE} does not look like Companion's licence.
  Expected the MIT text in Part 1. Check ${COMPANION_LICENCE_URL}."

# --- Offline module bundle ---------------------------------------------------
#
# There is no public API for bundles — it comes out of the Companion web UI
# (Modules -> offline bundle). So this one is supplied by hand, and the check
# that matters is that it is the SAME BUILD as the tarball above. A bundle from
# a different build will mostly work, which is worse than failing.

BUNDLE="${VENDOR}/${MODULE_BUNDLE}"

if [ ! -f "$BUNDLE" ]; then
  # Accept it from the usual download location as a convenience, but copy it in
  # rather than reaching outside the repo at build time.
  for cand in "$HOME/Downloads/${MODULE_BUNDLE}"; do
    if [ -f "$cand" ]; then
      log "staging module bundle from $cand"
      cp "$cand" "$BUNDLE"
      break
    fi
  done
fi

[ -f "$BUNDLE" ] || die "no ${MODULE_BUNDLE} in ${VENDOR}/.
  Download it from a running Companion ${COMPANION_VERSION}:
    Modules -> 'Offline module bundle' -> download
  and put it in ${VENDOR}/. It must be build ${COMPANION_BUILD}, matching
  COMPANION_TARBALL in build/config.sh."

log "module bundle staged: $(du -h "$BUNDLE" | cut -f1)"

# The bundle is a flat tree of <module>/companion/manifest.json — exactly the
# layout --extra-module-path expects, which is why there is no import step.
# Verify that, because a format change would produce an image with zero modules
# and no error anywhere.
#
# Same pipefail rule as above: count, do not `grep -q` a pipeline.
log "checking bundle layout"
manifests="$(tar -tzf "$BUNDLE" | grep -c '/companion/manifest\.json$' || true)"
[ "${manifests:-0}" -gt 100 ] \
  || die "only ${manifests:-0} */companion/manifest.json entries in ${MODULE_BUNDLE}.
  The bundle format changed, or this is not an offline module bundle.
  companion-play loads it via --extra-module-path, which requires
  <module>/companion/manifest.json."
log "bundle carries ${manifests} modules"

log "vendor artifacts ready"

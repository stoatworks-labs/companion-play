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
  log "downloading ${COMPANION_TARBALL} (~200 MiB)"
  curl -fSL --retry 3 -o "${TGZ}.part" "$COMPANION_URL"
  mv "${TGZ}.part" "$TGZ"
fi

# No published checksum to pin against, so assert on the shape instead: the
# install is `--strip-components=2 --wildcards '*/resources'`, and if that
# pattern matches nothing the extract silently produces an empty /opt/companion
# and the image boots into a service that exits immediately.
log "checking tarball layout"
tar -tzf "$TGZ" | grep -q '/resources/main\.js$' \
  || die "no */resources/main.js in ${COMPANION_TARBALL}.
  The tarball layout changed, or the download is truncated. The install in
  03-make-image.sh extracts '*/resources' and would silently produce an empty
  ${CP_INSTALL_DIR}."

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
log "checking bundle layout"
tar -tzf "$BUNDLE" | grep -q '/companion/manifest\.json$' \
  || die "no */companion/manifest.json in ${MODULE_BUNDLE}.
  The bundle format changed. companion-play loads it via --extra-module-path,
  which requires <module>/companion/manifest.json."

log "vendor artifacts ready"

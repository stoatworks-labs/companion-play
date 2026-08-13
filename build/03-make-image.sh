#!/usr/bin/env bash
# Turn the Armbian base image into a companion-play image.
#
# Everything Companion needs is a download and an untar — its linux-arm64 build
# ships its own Node runtimes (18/22/26) and its own native prebuilds, so there
# is no compile step anywhere in this file. The base OS supplies libraries only.
#
# Read docs/02-verification.md before changing the package list: each entry
# there has a measurement behind it, and `libatomic1` in particular fails in a
# way that looks like a corrupt download rather than a missing dependency.

. "$(dirname "$0")/lib.sh"

require_root
require_aarch64_linux
need rsync losetup growpart resize2fs e2fsck chroot tar

IMG="${OUT}/${IMAGE_NAME}.img"
ROOT="${WORK}/mnt"
TGZ="${CACHE}/${COMPANION_TARBALL}"
BUNDLE="${VENDOR}/${MODULE_BUNDLE}"

[ -f "${WORK}/base.img" ] || die "run 01-fetch-base.sh first"
[ -f "$TGZ" ]    || die "no ${TGZ} — run 02-fetch-companion.sh first"
[ -f "$BUNDLE" ] || die "no ${BUNDLE} — run 02-fetch-companion.sh first"

# --- How anyone gets in ------------------------------------------------------
#
# An appliance with no key AND no password is a brick, so refuse to build one.
# Which of the two is acceptable depends on who the image is for — see
# CP_DEFAULT_PASSWORD in config.sh.
KEYFILE="${REPO_ROOT}/secrets/authorized_keys"
HAVE_KEY=0
[ -s "$KEYFILE" ] && HAVE_KEY=1

if [ "$HAVE_KEY" = "0" ] && [ -z "$CP_DEFAULT_PASSWORD" ]; then
  die "no way into the image.
  Either put a public key in ${KEYFILE} (it is gitignored), or set
  CP_DEFAULT_PASSWORD in build/config.sh. With neither, the image boots, joins
  the network, and lets nobody in."
fi

if [ -n "$CP_DEFAULT_PASSWORD" ]; then
  warn "building with a DEFAULT PASSWORD for ${CP_ADMIN_USER}: ${CP_DEFAULT_PASSWORD}"
  warn "that is correct for a published image and wrong for a unit on a show"
  warn "network — clear CP_DEFAULT_PASSWORD for a key-only build."
fi

log "creating ${IMG}"
rm -f "$IMG"
cp --reflink=auto "${WORK}/base.img" "$IMG"

grow_image "$IMG" "${IMAGE_SIZE_GB}G"

part="$(attach_image "$IMG")"
mount_chroot "$part" "$ROOT"

# Guard against the trap that makes every later assertion pass vacuously: a
# mount that silently failed leaves an empty directory, and `[ ! -f ... ]`
# checks against it all trivially succeed.
[ -d "${ROOT}/etc" ] || die "chroot root is empty — the mount failed silently"

# --- packages ----------------------------------------------------------------
#
# Two groups, and they are worth keeping distinct.
#
# Companion's own dependencies come straight out of companion-pi's update.sh /
# install.sh. `libatomic1` is required by the bundled Node 26 and is the one
# that bites: without it the runtime dies with a shared-library error before it
# prints anything Companion-shaped.
#
# The display group is ours. companion-pi is headless; here the HDMI output is
# part of the product. A minimal window manager earns its place — without one,
# Chromium's tabs, fullscreen and dialogs have nothing to manage them.
log "installing packages"
in_chroot "$ROOT" apt-get update -qq
in_chroot "$ROOT" apt-get install -y -qq --no-install-recommends \
  libatomic1 \
  libfontconfig1 \
  libasound2 \
  libusb-1.0-0 \
  libudev1 \
  udev \
  ca-certificates \
  curl \
  unzip

log "installing display stack"
in_chroot "$ROOT" apt-get install -y -qq --no-install-recommends \
  xserver-xorg-core \
  xserver-xorg-input-libinput \
  xserver-xorg-video-fbdev \
  xinit \
  x11-xserver-utils \
  openbox \
  chromium \
  fonts-dejavu-core \
  unclutter

# --- Companion ---------------------------------------------------------------
#
# This is companion-pi's update.sh install, verbatim in effect: extract the
# `resources` directory of the release tarball to /opt/companion. Nothing else
# in that tarball is used on Linux.
log "installing Companion ${COMPANION_VERSION} (${COMPANION_BUILD})"
rm -rf "${ROOT}${CP_INSTALL_DIR}"
mkdir -p "${ROOT}${CP_INSTALL_DIR}"
tar -xzf "$TGZ" --strip-components=2 -C "${ROOT}${CP_INSTALL_DIR}" --wildcards '*/resources'

[ -f "${ROOT}${CP_INSTALL_DIR}/main.js" ] \
  || die "no main.js in ${CP_INSTALL_DIR} — the extract matched nothing"

echo "${COMPANION_VERSION}+${COMPANION_BUILD}" > "${ROOT}${CP_INSTALL_DIR}/.companion-play-version"

# --- modules -----------------------------------------------------------------
#
# The offline bundle is a flat tree of <module>/companion/manifest.json, which
# is precisely what --extra-module-path consumes. So it is an untar, not an
# import: no web UI step, no network, and the unit is fully useful the first
# time it boots on an isolated show network.
log "installing offline module bundle"
rm -rf "${ROOT}${CP_MODULE_DIR}"
mkdir -p "${ROOT}${CP_MODULE_DIR}"
tar -xzf "$BUNDLE" -C "${ROOT}${CP_MODULE_DIR}"

modcount="$(find "${ROOT}${CP_MODULE_DIR}" -maxdepth 3 -name manifest.json -path '*/companion/*' | wc -l)"
[ "$modcount" -gt 100 ] || die "only ${modcount} modules extracted — the bundle is not what we expect"
log "modules extracted: ${modcount}"

# --- module licence policy ---------------------------------------------------
#
# An image redistributes every module in it, which is not the same obligation as
# an operator downloading the bundle from Bitfocus. Keep only the licences on
# the allow-list, and write down what shipped.
#
# Runs the target's own Node inside the chroot — the same trick as config-tool,
# and the reason the build host has to be aarch64.
log "applying module licence policy"
mkdir -p "${ROOT}/usr/share/doc/companion-play"
install -D -m 0644 "${REPO_ROOT}/build/filter-modules.mjs" "${ROOT}/tmp/filter-modules.mjs"
in_chroot "$ROOT" "${CP_INSTALL_DIR}/node-runtimes/main/bin/node" \
  /tmp/filter-modules.mjs "$CP_MODULE_DIR" "$CP_LICENCE_ALLOW" \
  /usr/share/doc/companion-play/modules.tsv \
  || die "module licence policy failed — see the list above"
rm -f "${ROOT}/tmp/filter-modules.mjs"

modcount="$(find "${ROOT}${CP_MODULE_DIR}" -maxdepth 3 -name manifest.json -path '*/companion/*' | wc -l)"
log "modules shipped: ${modcount}"

# --- users -------------------------------------------------------------------
#
# Two accounts, deliberately. `companion` is the service account and matches
# companion-pi's name so that project's scripts and documentation apply
# unchanged. The human logs in as ${CP_ADMIN_USER} and never as the service.
log "creating users"

# Companion's state lives outside the rootfs so a reflash does not destroy an
# operator's configuration — see docs/03-installing.md. Its home IS that
# directory: Companion derives $HOME/.config/companion-nodejs from it, and
# companion-sync-udev-rules reads the home out of passwd, so pointing the home
# here is all that is needed.
mkdir -p "${ROOT}${CP_STATE_DIR}"
in_chroot "$ROOT" useradd -r -m -d "$CP_STATE_DIR" -s /usr/sbin/nologin \
  -G video,render,input,audio,dialout,plugdev "$CP_SERVICE_USER" 2>/dev/null || true
in_chroot "$ROOT" install -d -o "$CP_SERVICE_USER" -g "$CP_SERVICE_USER" \
  "${CP_STATE_DIR}/.config/companion-nodejs"

in_chroot "$ROOT" useradd -m -s /bin/bash \
  -G sudo,video,render,input,audio,plugdev "$CP_ADMIN_USER" 2>/dev/null || true

if [ -n "$CP_DEFAULT_PASSWORD" ]; then
  # A published image needs a login that works for whoever downloaded it.
  echo "${CP_ADMIN_USER}:${CP_DEFAULT_PASSWORD}" | in_chroot "$ROOT" chpasswd
else
  # Keys only. An appliance with a guessable password on a show network is
  # worse than one you have to bring a key to.
  in_chroot "$ROOT" passwd -l "$CP_ADMIN_USER" >/dev/null 2>&1 || true
fi

if [ "$HAVE_KEY" = "1" ]; then
  install -d -m 0700 "${ROOT}/home/${CP_ADMIN_USER}/.ssh"
  install -m 0600 "$KEYFILE" "${ROOT}/home/${CP_ADMIN_USER}/.ssh/authorized_keys"
  in_chroot "$ROOT" chown -R "${CP_ADMIN_USER}:${CP_ADMIN_USER}" "/home/${CP_ADMIN_USER}/.ssh"

  install -d -m 0700 "${ROOT}/root/.ssh"
  install -m 0600 "$KEYFILE" "${ROOT}/root/.ssh/authorized_keys"
fi

# Chromium's profile. Given an explicit path outside the admin user's home so
# that wiping a wedged browser profile is one obvious rm and cannot take an
# operator's shell history or keys with it.
in_chroot "$ROOT" install -d -o "$CP_ADMIN_USER" -g "$CP_ADMIN_USER" -m 0755 \
  /var/lib/companion-play-kiosk

# --- sudoers -----------------------------------------------------------------
#
# Companion 4.3+ generates udev rules at runtime and asks the OS to install
# them; without this the surface rules never land and Stream Decks are visible
# to root only. Lifted from companion-pi's 090-companion_sudo.
install -D -m 0440 /dev/stdin "${ROOT}/etc/sudoers.d/090-companion_sudo" <<EOF
${CP_SERVICE_USER} ALL=NOPASSWD: /sbin/reboot, /sbin/shutdown, /sbin/poweroff, /usr/local/sbin/companion-sync-udev-rules
EOF

# --- overlay -----------------------------------------------------------------
if [ -d "${REPO_ROOT}/overlay" ] && [ -n "$(ls -A "${REPO_ROOT}/overlay" 2>/dev/null)" ]; then
  log "applying overlay"
  rsync -a --no-owner --no-group "${REPO_ROOT}/overlay/" "${ROOT}/"
  chmod 0755 "${ROOT}/usr/local/sbin/companion-sync-udev-rules" \
             "${ROOT}/usr/local/bin/companion-play-mode" \
             "${ROOT}/usr/local/bin/companion-play-launch" \
             "${ROOT}/usr/local/bin/companion-play-kiosk" 2>/dev/null || true
fi

# --- Companion configuration -------------------------------------------------
#
# 5.x generates its launch flags from a YAML file. `init` is idempotent and
# additive — it creates the file with commented defaults, and on a later version
# only appends newly-introduced options — so it is safe to run on every build.
#
# This runs the *target's* bundled Node inside the chroot. That is only possible
# because the build host is aarch64 Linux; see playbase's require_aarch64_linux.
log "generating ${CP_INSTALL_DIR} config"
in_chroot "$ROOT" install -d -o root -g root -m 0755 /etc/companion
in_chroot "$ROOT" env COMPANION_CONFIG_FILE=/etc/companion/config.yaml \
  "${CP_INSTALL_DIR}/node-runtimes/main/bin/node" "${CP_INSTALL_DIR}/config-tool.js" init \
  --set "extraModulePath=${CP_MODULE_DIR}"

[ -s "${ROOT}/etc/companion/config.yaml" ] || die "config-tool produced no config.yaml"

in_chroot "$ROOT" chown -R "${CP_SERVICE_USER}:${CP_SERVICE_USER}" "$CP_STATE_DIR"

# --- services ----------------------------------------------------------------
log "configuring services"
in_chroot "$ROOT" systemctl enable ssh.service
in_chroot "$ROOT" systemctl set-default multi-user.target

# server mode is the default; satellite is present but not enabled. See
# companion-play-mode.
in_chroot "$ROOT" systemctl enable companion.service

if [ "$CP_KIOSK_ENABLED" = "1" ]; then
  in_chroot "$ROOT" systemctl enable companion-kiosk.service
fi

echo "$CP_HOSTNAME" > "${ROOT}/etc/hostname"
sed -i "s/127.0.1.1.*/127.0.1.1\t${CP_HOSTNAME}/" "${ROOT}/etc/hosts" 2>/dev/null || true

# --- Armbian quirks ----------------------------------------------------------
#
# ORDER MATTERS: armbian_unlock_login must run AFTER the last apt-get install.
# apt can reinstate the first-login gate, and a gate that comes back silently
# produces an image that boots, answers ping, and lets nobody in.
armbian_unlock_login "$ROOT"
armbian_enable_resize "$ROOT"

# Assert on the FINISHED image rather than trusting the step above. This check
# cannot be fooled by any disagreement about what the pristine base contains.
for gate in \
  /root/.not_logged_in_yet \
  /etc/profile.d/armbian-check-first-login.sh \
  /etc/profile.d/armbian-check-first-login-reboot.sh
do
  [ ! -e "${ROOT}${gate}" ] || die "first-login gate still present: ${gate}
  Something after armbian_unlock_login reinstated it (usually an apt install)."
done

# --- redistribution notices --------------------------------------------------
#
# The image carries Bitfocus's Companion build and several hundred third-party
# modules. MIT requires the copyright notice and licence text to travel with
# them, so they travel in the image, not only in the repo's ATTRIBUTIONS.md —
# the person holding a flashed card is the one who needs them.
#
# NOT conditional. An earlier version guarded this with `if [ -f … ]` on a path
# the tarball does not contain, so the build cheerfully produced an image whose
# ATTRIBUTIONS.md pointed at a licence file that was never installed. If the
# licence is missing, the right outcome is a failed build.
log "installing licence notices"
COMPANION_LICENCE="${CACHE}/companion-LICENSE-${COMPANION_VERSION}.md"
[ -s "$COMPANION_LICENCE" ] \
  || die "no ${COMPANION_LICENCE} — run 02-fetch-companion.sh.
  The image redistributes Companion; its licence text has to travel with it."
install -m 0644 "$COMPANION_LICENCE" \
  "${ROOT}/usr/share/doc/companion-play/companion-LICENSE.md"

install -m 0644 "${REPO_ROOT}/ATTRIBUTIONS.md" \
  "${ROOT}/usr/share/doc/companion-play/ATTRIBUTIONS.md"
install -m 0644 "${REPO_ROOT}/LICENSE" \
  "${ROOT}/usr/share/doc/companion-play/LICENSE"

# --- reclaim -----------------------------------------------------------------
#
# apt leaves its downloaded .debs and package lists behind, and on this image
# that was 388 MB of a 3.47 GiB total — measured, not guessed. It matters more
# here than on most appliances: the PLAY's rootfs partition is a fixed 3.5 GiB
# that cannot be grown, so this is the difference between fitting and not.
#
# Runs after the last apt work and after the first-login assertion, so it cannot
# disturb either.
log "reclaiming space"
in_chroot "$ROOT" apt-get clean
rm -rf "${ROOT}/var/lib/apt/lists/"*
rm -rf "${ROOT}/var/cache/apt/archives/"*.deb
rm -rf "${ROOT}/var/log/"*.log "${ROOT}/var/log/journal/"* 2>/dev/null || true

log "rootfs now uses $(du -sh --exclude=./proc --exclude=./sys --exclude=./dev "$ROOT" 2>/dev/null | cut -f1)"

# --- build stamp -------------------------------------------------------------
{
  echo "companion-play"
  echo "built:     $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "base:      ${ARMBIAN_IMAGE}"
  echo "companion: ${COMPANION_VERSION}+${COMPANION_BUILD}"
  echo "modules:   ${modcount} (licence policy: ${CP_LICENCE_ALLOW})"
  echo "kiosk:     ${CP_KIOSK_ENABLED}"
  echo "login:     ${CP_ADMIN_USER}$([ -n "$CP_DEFAULT_PASSWORD" ] && echo ' (default password set)')$([ "$HAVE_KEY" = 1 ] && echo ' + ssh key')"
} > "${ROOT}/etc/companion-play-build"

restore_resolv "$ROOT"
cleanup_chroot

log "image ready: ${IMG} ($(du -h "$IMG" | cut -f1))"
log "flash to a microSD. This is a WHOLE-DISK image (its own partition table,"
log "u-boot in the gap) — it cannot be dd'd into the PLAY's rootfs partition."
log "See docs/03-installing.md for the eMMC path."

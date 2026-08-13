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

# --- SSH keys ----------------------------------------------------------------
# A headless appliance with no key in it is a brick. Refuse to build one.
KEYFILE="${REPO_ROOT}/secrets/authorized_keys"
if [ ! -s "$KEYFILE" ]; then
  die "no ${KEYFILE}.
  Put at least one public key there (it is gitignored). Without it the image
  boots with no way in — there is no console password by design."
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
log "modules installed: ${modcount}"

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
# No password: keys only. An appliance with a guessable password on a show
# network is worse than one you have to bring a key to.
in_chroot "$ROOT" passwd -l "$CP_ADMIN_USER" >/dev/null 2>&1 || true

install -d -m 0700 "${ROOT}/home/${CP_ADMIN_USER}/.ssh"
install -m 0600 "$KEYFILE" "${ROOT}/home/${CP_ADMIN_USER}/.ssh/authorized_keys"
in_chroot "$ROOT" chown -R "${CP_ADMIN_USER}:${CP_ADMIN_USER}" "/home/${CP_ADMIN_USER}/.ssh"

install -d -m 0700 "${ROOT}/root/.ssh"
install -m 0600 "$KEYFILE" "${ROOT}/root/.ssh/authorized_keys"

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

# --- build stamp -------------------------------------------------------------
{
  echo "companion-play"
  echo "built:     $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "base:      ${ARMBIAN_IMAGE}"
  echo "companion: ${COMPANION_VERSION}+${COMPANION_BUILD}"
  echo "modules:   ${modcount}"
  echo "kiosk:     ${CP_KIOSK_ENABLED}"
} > "${ROOT}/etc/companion-play-build"

restore_resolv "$ROOT"
cleanup_chroot

log "image ready: ${IMG} ($(du -h "$IMG" | cut -f1))"
log "flash to a microSD. This is a WHOLE-DISK image (its own partition table,"
log "u-boot in the gap) — it cannot be dd'd into the PLAY's rootfs partition."
log "See docs/03-installing.md for the eMMC path."

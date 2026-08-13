#!/usr/bin/env bash
# Pinned inputs for a companion-play image build.
#
# Sourced by every build/NN-*.sh; not executable on its own.
#
# shellcheck disable=SC2034  # every variable here is consumed by a sourcing script

# --- Base OS -----------------------------------------------------------------
#
# Pinned in playbase/base.conf, shared with weblinked-os and polecat.
# ARMBIAN_BOARD / ARMBIAN_RELEASE / ARMBIAN_IMAGE / ARMBIAN_URL / ARMBIAN_SHA256
# all come from there — do not redefine them here, or a bump silently applies to
# only one appliance.

# --- Companion ---------------------------------------------------------------
#
# The official linux-arm64 tarball. companion-pi resolves this at install time
# through an interactive picker; an appliance image pins it instead, so a build
# is reproducible and an image's contents are knowable from this file.
#
# To bump: query the same API companion-pi uses, then update all three lines.
#   curl -s 'https://api.bitfocus.io/v1/product/companion/packages?branch=stable&limit=3&target=linux-arm64-tgz'
COMPANION_VERSION="5.0.3"
COMPANION_BUILD="9703-stable-2daa0d7670"
COMPANION_TARBALL="companion-linux-arm64-${COMPANION_VERSION}-${COMPANION_BUILD}.tar.gz"
COMPANION_URL="https://cf-pub.bitfocus.io/companion/companion/${COMPANION_TARBALL}"

# The offline module bundle, which MUST carry the same build id as the tarball
# above — Bitfocus publish them as a matched pair and 02-fetch-companion.sh
# refuses a mismatch.
#
# There is no public API listing bundles; it is downloaded from the Companion
# web UI. Drop it in vendor/ and the build will use it.
MODULE_BUNDLE="companion-offline-module-bundle-${COMPANION_VERSION}-${COMPANION_BUILD}.tar.gz"

# --- Module licence policy ---------------------------------------------------
#
# A companion-play image REDISTRIBUTES every module inside it. That is a
# different obligation from an operator downloading the bundle from Bitfocus
# themselves, so the image carries only licences on this list and
# build/filter-modules.mjs deletes the rest at build time.
#
# Measured on the 5.0.3 bundle (811 modules, every one declaring a licence in
# its manifest): 799 MIT, 9 ISC, 3 LGPL-3.0. The three LGPL modules —
# cleartouch-ippctrl, pnh-opencountdown, pnh-soundr — are removed, costing about
# 1.1 MB. Anyone who wants them can install them from a bundle downloaded from
# their own Companion, where no third party is redistributing anything.
#
# ISC is on the list because it is functionally MIT. Weak copyleft is not,
# because complying inside a binary image means shipping a source offer, and an
# appliance image is the wrong place to carry one.
CP_LICENCE_ALLOW="MIT,ISC,BSD-2-Clause,BSD-3-Clause,Apache-2.0,0BSD,Unlicense,CC0-1.0"

# --- Login -------------------------------------------------------------------
#
# Two shapes, because a public image and a private one want opposite things.
#
# With CP_DEFAULT_PASSWORD set, the image ships a documented default password —
# the Armbian/Raspberry Pi OS convention, and the only thing that makes a
# published image usable by anyone other than whoever built it.
#
# With it empty, the build REQUIRES secrets/authorized_keys and produces a
# key-only image with the password locked. That is the right shape for a unit
# going on a show network and is what a private build should use.
#
# Both may be set: keys are installed whenever secrets/authorized_keys exists.
CP_DEFAULT_PASSWORD="companion"

# --- Image -------------------------------------------------------------------
#
# Armbian expands the rootfs to fill the card on first boot, so this only has to
# hold the build product. Unlike polecat, that product is large: /opt/companion
# is 588 MB, the extracted module bundle is 459 MB, and Chromium and X are on
# top of the base. See docs/02-verification.md for the measurements.
IMAGE_SIZE_GB="6"
IMAGE_NAME="companion-play-${ARMBIAN_RELEASE}"

# --- Appliance ---------------------------------------------------------------
CP_HOSTNAME="companion-play"
CP_ADMIN_USER="cplay"          # the human's login — NOT the service account
CP_SERVICE_USER="companion"    # matches companion-pi, so its docs and scripts apply

# Where Companion's own files go. /opt/companion is companion-pi's path and is
# kept, so anyone who knows Companion Pi knows this box.
CP_INSTALL_DIR="/opt/companion"

# The extracted offline bundle. Companion takes exactly ONE --extra-module-path,
# so this is it: the bundle's 811 modules and any hand-added module share the
# directory. (companion-pi points that single path at /opt/companion-module-dev
# and ships no bundle; an appliance has the opposite priority.)
CP_MODULE_DIR="/opt/companion-modules"

# Companion's mutable state — config, database, logs, user-installed modules.
# On an installed unit this is the PLAY's `userdata` partition (p9), so
# reflashing the rootfs does not wipe an operator's configuration. On an SD
# image it is just a directory. See docs/03-installing.md.
CP_STATE_DIR="/var/lib/companion-play"

# --- Display -----------------------------------------------------------------
#
# The HDMI output is part of the product: the unit shows Companion's own web UI
# and its web-button pages. Chromium rather than a bare kiosk shell because the
# operator wants tabs, a keyboard and a mouse.
CP_KIOSK_ENABLED="1"
CP_KIOSK_URL="http://127.0.0.1:8000/"

# --- Paths -------------------------------------------------------------------
WORK_DIR="work"
OUT_DIR="out"
CACHE_DIR="cache"
VENDOR_DIR="vendor"

#!/usr/bin/env bash
# Fetch and unpack the pinned Armbian base image.
#
# Thin wrapper over playbase's fetch_base — the pin, the checksum and the
# decompression all live there, shared with the other PLAY appliances.

. "$(dirname "$0")/lib.sh"

fetch_base "$CACHE" "${WORK}/base.img" "${1:-}"

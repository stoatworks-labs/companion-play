# companion-play

A **replacement OS for the BirdDog PLAY** (Rockchip RK3328) that turns it into a
self-contained **Bitfocus Companion** appliance: the server, its web UI on the
HDMI output, and USB surfaces on the front port.

This is the third appliance built on [`playbase`](../playbase), alongside
[`weblinked-os`](../weblinked-os) (browser endpoint) and
[`polecat`](../polecat) (KVM console). It is the same Armbian `renegade` base
and the same two-partition install; only the payload differs.

## Why a PLAY

Not for the silicon — Companion uses none of the PLAY's video hardware. The
reason is **supply**: PLAYs are bought cheap in quantity, and a converted one is
a fanless, metal-cased, PoE-adjacent aarch64 box with HDMI, gigabit and USB host
— which is exactly the shape of a Companion appliance, and better packaged than
a Pi in a case.

The one thing the hardware does buy is the **HDMI output**. Companion Pi is
headless and its screen shows nothing. Here the display is part of the product:
the PLAY drives a monitor showing Companion's own web UI and its Tablet/web
button pages, so the unit is both the server *and* an operator surface.

## What it runs

| Piece | What |
|---|---|
| Base | Armbian `renegade`, Debian **trixie**, 26.8.1 minimal — pinned in `playbase/base.conf` |
| Companion | Official **`linux-arm64`** build, unpacked to `/opt/companion`. No compiling. |
| Modules | The official **offline module bundle**, 811 modules, preloaded. No internet needed to be useful. |
| Display | Bare X + a minimal WM + Chromium, showing the admin UI and web-button pages as tabs |
| Input | USB keyboard, mouse, touchscreen and Stream Decks on the single USB-A port (via a hub) |

Companion's Linux build ships **its own Node runtimes** (18/22/26, arm64) and
its own native prebuilds, so the base OS supplies only libraries:
`libatomic1`, `libfontconfig1`, `libasound2`, `libusb-1.0-0`, `libudev1`.

## Two modes, one image

`companion-play-mode server|satellite` switches the unit between:

- **server** (default) — the full Companion host. Admin UI on `:8000`.
- **satellite** — Companion Satellite, driving this unit's surfaces from a
  Companion running elsewhere. Useful for a fleet of PLAYs feeding one server.

The image carries both; the mode is a systemd unit selection, not a reflash.

## Install model

Inherited from `polecat`, because it is the property that makes this safe:
**only `boot` (p4) and `rootfs` (p8) are replaced.** `uboot`, `trust`, `misc`
and `recovery` stay stock, so Rockchip recovery mode *and* the vendor recovery
partition both survive. A normal install is two `dd`s and a reboot over SSH.

`userdata` (p9, grows to the end of the eMMC) is mounted for Companion's
config, database, logs and user-installed modules — so **reflashing the rootfs
does not wipe an operator's configuration.**

If the microSD slot turns out to be physically fitted, develop from a card
instead and never touch eMMC. That question is still open; see
[`docs/03-installing.md`](docs/03-installing.md).

## Status

**Nothing has run on PLAY hardware.** What *is* proven, on aarch64 Linux, is
in [`docs/02-verification.md`](docs/02-verification.md) — including a full
Companion 5.0.3 start with all 811 bundled modules loaded.

## Build

An aarch64 Linux host, as root. See [`docs/04-building.md`](docs/04-building.md).

```bash
build/mk
```

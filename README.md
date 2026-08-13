# companion-play

> **AI-assisted project.** This codebase was created with [Claude](https://claude.com/claude-code)
> (Anthropic), directed and reviewed by a human author. Companion 5.0.3 has been
> started on aarch64 Linux with the full offline module bundle — all 811 modules
> enumerated, admin UI answering, surface plugins running — but **no part of this
> has ever run on BirdDog PLAY hardware**, and the display, the installer and the
> USB surface path are unverified. See [docs/02-verification.md](docs/02-verification.md).

> ### ⚠️ Early beta
>
> Treat this as a design that boots on paper. The image builds and the software
> stack is proven on the right CPU architecture; the hardware half is not.
> Do not put this on a unit you need for a show.

A **replacement OS for the BirdDog PLAY** (Rockchip RK3328) that turns it into a
self-contained [Bitfocus Companion](https://bitfocus.io/companion) appliance:
the server, its web UI on the HDMI output, and USB surfaces on the front port.

## Why a PLAY

Not for the silicon — Companion uses none of the PLAY's video hardware. The
reason is **supply**: PLAYs turn up cheap in quantity, and one is a fanless,
metal-cased aarch64 box with HDMI, gigabit Ethernet and USB host. That is the
shape of a Companion appliance, and better packaged than a Pi in a case.

The one thing the hardware does buy is the **HDMI output**. Companion Pi is
headless and its screen shows nothing. Here the display is part of the product:
the PLAY drives a monitor showing Companion's own web UI and its web-button
pages as tabs, so the unit is both the server *and* an operator surface.

## What it runs

| Piece | What |
|---|---|
| Base | Armbian `renegade`, Debian **trixie**, 26.8.1 minimal — pinned by checksum |
| Companion | Official **`linux-arm64`** build, unpacked to `/opt/companion`. Nothing compiles. |
| Modules | The official offline module bundle, licence-filtered, preloaded. No internet needed to be useful. |
| Display | Bare X + openbox + Chromium, admin UI and web-button pages as tabs |
| Input | USB keyboard, mouse, touchscreen and Stream Decks — **via a powered hub**, see below |

Companion's Linux build ships **its own Node runtimes and native prebuilds**, so
the base OS supplies libraries only: `libatomic1`, `libfontconfig1`,
`libasound2`, `libusb-1.0-0`, `libudev1`.

## Two modes, one image

```
companion-play-mode server|satellite|status
```

- **server** (default) — the full Companion host, admin UI on `:8000`.
- **satellite** — Companion Satellite, driving this unit's surfaces from a
  Companion running elsewhere. **Scaffolded, not verified**: the switch refuses
  unless the binary is present, rather than stopping the server and starting
  nothing.

## Install model

**Only `boot` (p4) and `rootfs` (p8) are replaced.** `uboot`, `trust`, `misc`
and `recovery` stay stock, so Rockchip recovery mode *and* the vendor recovery
partition both survive — the device can be returned to factory firmware.

`userdata` (p9, which grows to the end of the eMMC) holds Companion's config,
database, logs and any modules you add, so **reflashing the rootfs to upgrade
Companion does not wipe your configuration**.

If the PLAY's microSD slot turns out to be physically fitted — still an open
question — you can run entirely from a card and never touch the eMMC. See
[docs/03-installing.md](docs/03-installing.md).

## Default login

Released images ship with a **default password**, which is the only thing that
makes a published image usable by anyone but its builder:

```
user: cplay    password: companion
```

**Change it.** `passwd` on first login. If you are building your own image, put
a public key in `secrets/authorized_keys` and clear `CP_DEFAULT_PASSWORD` in
`build/config.sh` for a key-only image with no password at all — the right shape
for anything going on a show network.

## Known limits

- **2 GB of RAM is the real constraint.** Companion idles at ~509 MB with zero
  connections, and every connection is another Node child process. Chromium is
  on top of that. No connection count has been measured; do not assume one.
- **One USB-A port.** Keyboard, mouse, touchscreen and a Stream Deck all want
  it, so a **self-powered hub** is required. The port's current budget has not
  been measured, and a bus-powered hub with a Stream Deck on it is exactly the
  case that fails.
- **Nothing has run on hardware.** Repeated because it matters.

## Build

An aarch64 Linux host, as root — the build runs the target's own binaries in a
chroot, including Companion's bundled Node. See
[docs/04-building.md](docs/04-building.md).

```bash
build/mk
```

You supply the offline module bundle (downloaded from your own Companion's
Modules page); everything else is fetched and checksummed.

## This is not a BirdDog or Bitfocus product

Neither company is affiliated with this, endorses it, or supports it.
Installing it **voids your warranty** and removes the NDI and SRT decoding the
device was sold to do. It ships no BirdDog code, firmware or keys, and none is
needed to build or use it. See [ATTRIBUTIONS.md](ATTRIBUTIONS.md).

## Licence

MIT — see [LICENSE](LICENSE). A built *image* redistributes other people's work
under their own licences; [ATTRIBUTIONS.md](ATTRIBUTIONS.md) is the authority on
that, and every module in an image is listed with its licence at
`/usr/share/doc/companion-play/modules.tsv`.

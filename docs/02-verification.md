# 02 — Verification

What has actually been measured, what it cost, and what is still assumed.
Nothing in this file is inferred from documentation; every line has a command
behind it. **No PLAY hardware has run any of this.**

Measured 2026-08-13 on the shared aarch64 build VM (`tart` `wlos-build`,
Ubuntu 24.04 aarch64, 10 cores / 16 GB) unless stated otherwise.

## Inputs

Two files, and they are a **matched pair** — same build id `9703-stable-2daa0d7670`:

| File | Size |
|---|---|
| `companion-pi-stable-v5.0.3-05-08-26.img.xz` | 800 MB (4.8 GB raw) |
| `companion-offline-module-bundle-5.0.3-9703-stable-2daa0d7670.tar.gz` | 156 MB (**459 MB** raw) |

The image is only a *reference*: the build downloads the official tarball
instead, from the same API companion-pi uses.

```
https://api.bitfocus.io/v1/product/companion/packages?branch=stable&limit=3&target=linux-arm64-tgz
  -> https://cf-pub.bitfocus.io/companion/companion/companion-linux-arm64-5.0.3-9703-stable-2daa0d7670.tar.gz
```

## The single most useful finding: the base OS matches

**Companion Pi 5.0.3 is Debian 13 trixie.** `playbase`'s pinned Armbian
`renegade` image is *also* trixie. Same glibc, same `libusb`/`libudev`
sonames, same everything Companion links against.

That collapses the largest risk in the port. There is no cross-distro
compatibility work, no glibc floor to clear (`update.sh` demands ≥ 2.31; trixie
ships far newer), and no rebuild of native modules.

## Installing Companion is an untar

Read out of `/usr/local/src/companionpi/update.sh` in the image. The entire
install is:

```bash
tar -xzf companion-linux-arm64-*.tar.gz --strip-components=2 \
    -C /opt/companion --wildcards '*/resources'
```

Plus a config file, a systemd unit, a sudoers line and five apt packages. There
is **no build step, no `npm install`, no native compilation** — Companion's
Linux tarball is fully self-contained.

### What it needs from the OS

`update.sh` installs exactly these, and nothing else matters:

| Package | For |
|---|---|
| `libatomic1` | **required by the bundled Node 26** |
| `libfontconfig1` | the button canvas renderer |
| `libasound2` (`libasound2t64` on Ubuntu) | `generic-midi` |
| `libusb-1.0-0-dev`, `libudev-dev` | USB surfaces (from `install.sh`) |

**`libatomic1` is not optional and fails in a confusing way.** Without it the
bundled runtime dies before printing anything Companion-shaped:

```
node: error while loading shared libraries: libatomic.so.1: cannot open shared object file
```

Hit on the first attempt to run `config-tool.js`. It reads as a broken
download, not a missing dependency.

## Companion 5.0.3 runs on aarch64 with the full module bundle — PROVEN

The bundle extracts to **811 module directories**, each `<module>/companion/manifest.json`
— which is exactly the layout `--extra-module-path` expects. So the offline
bundle needs no import step: point Companion at the extracted directory.

```bash
node ./main.js --admin-port 8000 --extra-module-path /tmp/modules --enable-restricted-modules
```

Result:

- **All 811 modules enumerated** and listed as `(Dev & Packaged)`.
- Admin UI answered **HTTP 200** on `:8000`.
- Surface plugins started as child processes: `elgato-stream-deck`, `xkeys`.
- `Instance/UdevRules  Regenerating udev rules for surface modules` — the 4.3+
  runtime rule generation is live and will need the sudoers helper.
- Bundled runtime reports **`v26.5.0`**; `node-runtimes/main` is a symlink to
  `node26`, and surface children ran under **`node22`**.

### Memory, which is the real constraint

2 GB is the whole budget on a PLAY. Idle, immediately after start:

| Process | RSS |
|---|---|
| `main.js` (MainThread) | **324 MB** |
| `SurfaceThread.js` (elgato-stream-deck) | 92 MB |
| `SurfaceThread.js` (xkeys) | 93 MB |
| **Total, zero connections configured** | **~509 MB** |

Every Companion *connection* is a separate Node child process, so the per-
connection cost is expected to be in the same ~70–100 MB band as these surface
children. **That is the number that decides how many connections a PLAY can
hold**, and it has not been measured yet — see Open questions.

> Measurement trap, hit here: a second pass grepping `ps` for
> `comp/node-runtimes` reported 185 MB and looked like a much better result. It
> was wrong — the main process was launched with a *relative* path
> (`./node-runtimes/main/bin/node`), so the pattern silently excluded the
> largest process. Match on `main.js`, not on the runtime path.

## Module licences — scanned, not assumed

An image redistributes every module inside it, so all 811 were scanned from
their `companion/manifest.json` (falling back to `package.json`):

| Licence | Modules |
|---|---|
| MIT | **799** |
| ISC | 9 |
| LGPL-3.0 | 3 |

**Every one of the 811 declares a licence, and all 811 declare it in the
manifest** — the `package.json` fallback never fired. That is a better result
than expected for 811 community modules, and it is what makes a redistributable
image defensible at all.

The three LGPL-3.0 modules are `cleartouch-ippctrl` (0.0.5),
`pnh-opencountdown` (2.0.2) and `pnh-soundr` (2.0.2), together about **1.1 MB**.
They are excluded from the image by `build/filter-modules.mjs`. Nothing large or
widely used is lost.

`build/filter-modules.mjs` **fails the build** on a module that declares no
licence, rather than skipping it. Undeclared is not permissive, and a silent
skip is precisely the outcome the check exists to prevent.

## Disk

Measured on the finished image, not estimated from the parts:

| Item | Size |
|---|---|
| `/usr` (Armbian minimal + X + openbox + Chromium) | **2.0 GB** |
| — of which `/usr/lib/chromium` | 366 MB |
| `/opt` | **1.1 GB** |
| — `/opt/companion` | 588 MB |
| — — of which `node-runtimes/` (node18 90 + node22 119 + node26 142) | 351 MB |
| — `/opt/companion-modules` (808 modules, post-filter) | 458 MB |
| `/boot` | 116 MB |
| `/var` | 26 MB |
| **Total used** | **3.12 GiB** (3,349,229,568 bytes) |

### The estimate was wrong, and it mattered

An earlier version of this file predicted "roughly 2.6–2.7 GB". The first real
build came out at **3.47 GiB** — against a `rootfs` partition (p8) of exactly
**3.5 GiB**, which after ext4 metadata and journal leaves about 3.4 GiB usable.
**It did not fit**, and only building it showed that. X and Chromium cost
considerably more than guessed.

**388 MB of that was apt's leftovers** — downloaded `.deb`s and package lists,
never cleaned. `apt-get clean` plus removing `/var/lib/apt/lists` recovered
**362 MB** and took `/var` from 388 MB to 26 MB. That is the difference between
fitting and not, on a partition that cannot be grown.

Current headroom against p8: roughly **280 MB**. Not comfortable.

Trimmable if it gets tight, in order of return: **`node18` (90 MB)** if no
bundled module requires it — **unverified, check before cutting**; Companion's
`.map` files (~27 MB); `docs.zip` (10 MB). Beyond that, `/opt/companion-modules`
(458 MB) can move to `userdata` alongside the rest of the state, which is the
real answer if the base ever grows.

## Configuration is a generated YAML

5.x ships `/opt/companion/config-tool.js`; `launch.sh` sources its `generate`
output. `init` is idempotent and additive, which is what makes it safe to run on
every image build.

```bash
COMPANION_CONFIG_FILE=/etc/companion/config.yaml \
  node /opt/companion/config-tool.js init --set extraModulePath=/opt/companion-modules
```

15 options; the ones that matter to an appliance are `adminPort` (8000),
`adminAddress`, `extraModulePath`, `enableShellCommandSupport` (default
**false**), `enableRestrictedModules` (default **true**) and `disableIpv6`.

`generate` emits a `set --` line, so flags stay in one place:

```
set -- --admin-port 8000 --extra-module-path /opt/companion-modules --enable-restricted-modules
```

## Open questions

Ordered by how much they would change the design.

1. **Per-connection RSS.** Everything about how many connections a 2 GB PLAY
   can carry rests on this, and it is a half-hour measurement on the same VM:
   add connections, watch total RSS. Do this before promising anyone a number.
2. **Chromium's memory cost alongside Companion.** The display is a product
   requirement, and a browser plus a 509 MB idle server on a 2 GB box is the
   headline risk. Measure on the VM under a cgroup capped at 2 GB before
   assuming the combination fits.
3. **USB: one port, four wanted devices.** Keyboard, mouse, touchscreen and a
   Stream Deck all want the single USB-A. Earlier research on this hardware
   already flags that a hub is required and that the port's current budget is
   unmeasured — a bus-powered hub with a Stream Deck on it is exactly the case
   that fails. A self-powered hub is the safe assumption until measured.
4. **Companion Satellite arm64 artifacts.** Assumed to exist; the release page
   did not render its asset list. Confirm before claiming satellite mode works.
5. **Is the microSD slot fitted?** Unchanged from the sibling appliance
   projects: insert a card, look for `mmcblk0`. If fitted, every experiment
   becomes reversible by pulling the card.
6. **Touchscreen under X.** `hid-multitouch` is a module in Armbian's 6.18
   kernel and `xf86-input-libinput` handles the rest, but no specific panel has
   been tried, and calibration may be needed.

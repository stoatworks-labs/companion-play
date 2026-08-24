# Notes

Working notes for this repo: status, decisions, and the traps that have actually bitten.
Migrated out of Claude Code's memory on 2026-08-24, so they are written in the first
person and dated by when each thing was learned — that date is usually the useful part.

Cross-cutting notes that are not specific to this repo live in
[fleet-notes](https://github.com/stoatworks-labs/fleet-notes).

*companion-play — PRIVATE replacement OS turning a BirdDog PLAY into a Bitfocus Companion appliance; third playbase consumer*

`~/Projects/companion-play` — **PUBLIC** `stoatworks-labs/companion-play`,
created 2026-08-13, branch `main`. **Release `v0.1.0` is LIVE, marked
prerelease/"early beta"** — `companion-play-26.8.1.img.xz` (1.04 GiB),
`modules.tsv`, `SHA256SUMS`. Turns a BirdDog PLAY (RK3328) into a
**Bitfocus Companion** appliance: server + HDMI web UI + USB surfaces. Third
consumer of [playbase](https://github.com/stoatworks-labs/playbase/blob/main/docs/NOTES.md) (`playbase`), after [weblinked os](https://github.com/stoatworks-labs/weblinked-os/blob/main/docs/NOTES.md) (`weblinked-os`) and
[polecat](https://github.com/stoatworks-labs/polecat/blob/main/docs/NOTES.md) (`polecat`) — same Armbian `renegade` base, same two-partition install.

**The port is mostly assembly, and three measured facts are why:**
- **Companion Pi 5.0.3 is Debian 13 trixie, and so is playbase's pinned Armbian
  renegade.** Same glibc, same sonames — the entire cross-distro risk is gone.
- **Companion's `linux-arm64` tarball is self-contained**: its own Node runtimes
  (18/22/**26**, `main`->node26) and its own native prebuilds. The whole install
  is `tar -xzf … --strip-components=2 -C /opt/companion --wildcards '*/resources'`.
  **Nothing compiles anywhere.** If something looks like it needs `npm install`,
  the diagnosis is wrong.
- **The offline module bundle is already in `--extra-module-path` shape** — 811
  dirs of `<module>/companion/manifest.json`. So modules are an untar too: no
  web-UI import, no network on first boot.

**PROVEN on aarch64** (tart `wlos-build`, Ubuntu 24.04 aarch64, 2026-08-13):
Companion 5.0.3 started, enumerated **all 811** bundled modules, HTTP **200** on
`:8000`, started `elgato-stream-deck` + `xkeys` surface children, and logged
`Regenerating udev rules for surface modules`. **Nothing has run on PLAY
hardware.**

**`libatomic1` is required by the bundled Node 26 and fails misleadingly** —
`node: error while loading shared libraries: libatomic.so.1` before anything
Companion-shaped prints, which reads as a corrupt download. Full OS dep list is
just `libatomic1 libfontconfig1 libasound2 libusb-1.0-0 libudev1`.

**RAM is THE constraint: 2 GB.** Idle, zero connections: `main.js` **324 MB** +
~92 MB per surface child = **~509 MB**. Every *connection* is another Node child
in the same band, so per-connection RSS decides how many a PLAY holds — **not
yet measured**. Chromium on top is the headline risk.
- **Measurement trap paid for here:** grepping `ps` for `comp/node-runtimes`
  reported a flattering 185 MB and **silently excluded the main process**, which
  was launched with a *relative* path (`./node-runtimes/main/bin/node`). Match on
  `main.js`.

Disk: `/opt/companion` **588 MB** (351 MB of it node runtimes), extracted bundle
**459 MB**; PLAY rootfs p8 is a fixed **3.5 GiB**, build uses ~2.6-2.7 GB.
Hence: **Companion's state (`/var/lib/companion-play`, the service account's
home) goes on `userdata` p9** — removes growth from the partition that can't
grow, and makes a rootfs reflash an upgrade that **preserves operator config**.

Pinned build = `5.0.3+9703-stable-2daa0d7670`; tarball and module bundle are a
**matched pair sharing that build id**. Tarball URL comes from the same API
companion-pi uses:
`https://api.bitfocus.io/v1/product/companion/packages?branch=stable&limit=3&target=linux-arm64-tgz`.
There is **no public API for the module bundle** — download it from a running
Companion's Modules page. Neither artifact is ever committed.

Config: 5.x generates launch flags from `/etc/companion/config.yaml` via
`/opt/companion/config-tool.js init|generate|validate`; `init` is idempotent and
additive, so it is safe on every build. Built in the chroot with the *target's*
Node — only possible because the build host is aarch64.

Display is ours, not inherited: X + **openbox** + Chromium **with tabs**. Do NOT
use `chromium --kiosk` — it removes the tab strip and blocks fullscreen, and the
operator wants the admin UI plus web-button pages as tabs with kbd/mouse/touch.
GPU off by default (Mali-450 GLES2; a broken GL stack shows a blank window, not
an error).

**One USB-A port** for keyboard + mouse + touchscreen + Stream Deck → a
**self-powered hub** is required; the port's current budget is still unmeasured
([birddog re](https://github.com/stoatworks-labs/birddog-re/blob/main/docs/NOTES.md) (`birddog-re`) notes/05).

**Why it can be PUBLIC** (same test as [birddog play patcher](https://github.com/stoatworks-labs/birddog-play-patcher/blob/main/docs/NOTES.md) (`birddog-play-patcher`)): it needs
**no AES key, no vendor firmware, no BirdDog file at all** — it replaces the OS
rather than repackaging theirs. Adding anything that needs a vendor file would
end that. MIT licence, AI disclaimer, ATTRIBUTIONS.md, CI, dependabot all in.

**Module licence scan (measured 2026-08-13, all 811):** **799 MIT, 9 ISC, 3
LGPL-3.0**, and **every one declares a licence in its `companion/manifest.json`**
— the `package.json` fallback never fired. An image REDISTRIBUTES modules (unlike
an operator downloading Bitfocus's bundle), so `build/filter-modules.mjs` ships
only allow-listed licences and **fails the build on an undeclared one**. The 3
LGPL dropped are `cleartouch-ippctrl`, `pnh-opencountdown`, `pnh-soundr` (~1.1 MB)
→ **808 ship**.

**SIZE: the estimate was wrong and only a real build showed it.** Predicted
2.6–2.7 GB; first build was **3.47 GiB** against a p8 rootfs of exactly 3.5 GiB
(~3.4 GiB usable after ext4 overhead) — **it did not fit**. **388 MB was apt's
uncleaned `.deb`s + lists**; `apt-get clean` + `rm /var/lib/apt/lists/*` recovered
**362 MB** (/var 388 MB → 26 MB). Now **3.12 GiB, ~280 MB headroom**. Breakdown:
/usr 2.0 GB (chromium 366 MB), /opt 1.1 GB (companion 588 + modules 458), /boot
116 MB. If the base grows, move `/opt/companion-modules` to userdata too.

**TRAP HIT AGAIN — [pipefail grep q trap](https://github.com/stoatworks-labs/fleet-notes/blob/main/notes/reference_pipefail_grep_q_trap.md).** `tar -tzf … | grep -q …`
under playbase's `set -o pipefail`: grep -q exits at first match, tar takes
SIGPIPE, **a SUCCESSFUL match fails the build**. Presented as "the tarball layout
changed" on a perfectly good download. Count into a listing file instead.
(Layout is `companion-arm64/resources/main.js` — one leading component, and
companion-pi's `--strip-components=2` strips `companion-arm64/` + `resources/`.)

**Companion's own `LICENSE.md` is NOT in the release tarball** (it lives inside
`app.asar`; the tarball has only Electron/Chromium/Node licences). A guarded
`if [ -f … ]` copy therefore did nothing and shipped an ATTRIBUTIONS.md pointing
at a file that did not exist. Fetch it from
`raw.githubusercontent.com/bitfocus/companion/v<VERSION>/LICENSE.md` and install
it unconditionally. **Companion core is MIT** (Part 1; Part 2 is a contributor
CLA, not a redistribution restriction) — GitHub's API says `NOASSERTION`, which
is a classification failure, not a licensing problem.

Published images ship **`cplay` / `companion`** as a documented default password
(no forced change); clearing `CP_DEFAULT_PASSWORD` + supplying
`secrets/authorized_keys` restores the key-only build, and the build refuses to
produce an image with neither.

Satellite mode is **scaffolded, not verified** — `companion-play-mode` refuses to
switch unless `/opt/companion-satellite/companion-satellite` exists, because
enabling a unit with a missing ExecStart would stop the server and start nothing.

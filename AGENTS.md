# AGENTS.md — companion-play

A replacement OS for the **BirdDog PLAY** (Rockchip RK3328) that turns it into a
**Bitfocus Companion** appliance — server, display and USB surfaces in one box.
**Private repo.**

Read [`README.md`](README.md) for the architecture and
[`docs/02-verification.md`](docs/02-verification.md) for what is actually
proven. This file is the operating rules.

## Where this sits

Third consumer of [`playbase`](../playbase), after
[`weblinked-os`](../weblinked-os) and [`polecat`](../polecat). Sibling checkouts
under `~/Projects` are assumed: **`playbase`** (required — the shared base OS
and build plumbing), `polecat` and `weblinked-os` (the other two appliances,
whose install and display work this reuses), and `birddog-re` (the research that
justifies every hardware claim).

**`birddog-re` is local-only, has no git remote, and must stay that way** — its
history contains a recovered vendor AES key and a decrypted firmware blob.
Never copy key material, decrypted vendor firmware, or BirdDog binaries here.
companion-play replaces BirdDog's userspace; it does not redistribute it.

**Never vendor a copy of playbase.** Add to it or keep the change in `build/`.
A forked copy that quietly diverges is the exact mistake that repo exists to
prevent.

## Hard rules

1. **Never commit Companion's bytes.** The release tarball and the offline
   module bundle are Bitfocus's to distribute. This repo pins versions in
   `build/config.sh` and downloads at build time; `vendor/` is gitignored and
   stays that way.
2. **Never break the way back.** Only `boot` (p4) and `rootfs` (p8) are
   replaced. `uboot`, `trust`, `misc` and `recovery` stay stock so Rockchip
   recovery mode and the vendor recovery partition both survive. Dump a unit
   before taking it — factory recovery restores factory state, not that unit's
   provisioned serial, hostname or `/userdata`.
3. **`armbian_unlock_login` runs after the LAST `apt-get install`.** apt can
   reinstate Armbian's first-login gate, and a gate that comes back produces an
   image that boots, answers ping and lets nobody in. `03-make-image.sh` asserts
   on the finished image; keep that assertion below every install.
4. **Companion's state is not on the rootfs.** `/var/lib/companion-play` is the
   service account's home and is mounted from `userdata` (p9) on an installed
   unit, so reflashing the rootfs does not destroy an operator's configuration.
   Anything that writes an operator's data to the rootfs is a bug.
5. **There is no build step, and there must not be one.** Companion's
   `linux-arm64` tarball ships its own Node runtimes and its own native
   prebuilds. If something appears to need `npm install` or a compiler, the
   diagnosis is wrong — check `docs/02-verification.md` first.
6. **Do not reach for `chromium --kiosk`.** The display exists so an operator
   can keep the admin UI and web-button pages open as tabs. Kiosk mode removes
   the tab strip and blocks the fullscreen toggle.
7. **2 GB of RAM is the budget, and it is the real constraint.** Companion idles
   at ~509 MB with zero connections, and every connection is another Node child
   process. Measure before promising anyone a connection count.
8. **Check whether a conclusion from `birddog-re` depends on the VPU before
   reusing it.** Several rulings there invert between video and non-video
   designs, and this has already caused one wrong conclusion elsewhere in the
   fleet. companion-play decodes nothing, so the "no browser on the PLAY" ruling
   does not reach it — that was about software-decoding 4K H.264 while the VPU
   idled.

## Test units

One PLAY is provisioned and reachable: `.42`, **stock firmware 1.0.30**, SSH on
port **9031**, on the tailnet as `birddog-play-42` (`100.88.59.79`). It is the
reference for how the hardware behaves. **Do not reflash it without saying so.**

The build host is the shared `tart` VM **`wlos-build`** (aarch64 Linux, root).
It is shared with the other two appliance projects — check for co-session
activity (`losetup -a`, running builds) before doing anything destructive, and
only detach loop devices you attached.

## Conventions

- Shell for the build; the appliance carries no compiled code of ours.
- Notes go in `docs/`, numbered, in the style of `birddog-re/notes/`: what was
  established, what it cost, and what is still assumed. A claim with no command
  behind it is labelled as an assumption.

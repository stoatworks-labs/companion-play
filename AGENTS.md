# AGENTS.md — companion-play

A replacement OS for the **BirdDog PLAY** (Rockchip RK3328) that turns it into a
**Bitfocus Companion** appliance — server, display and USB surfaces in one box.
**Public repo, early beta.**

Read [`README.md`](README.md) for the architecture and
[`docs/02-verification.md`](docs/02-verification.md) for what is actually
proven. This file is the operating rules.

## Where this sits

Third consumer of `playbase`, the shared Armbian base and build plumbing for
BirdDog PLAY appliance images, after `weblinked-os` and `polecat`. A sibling
checkout at `../playbase` is **required**; override with `PLAYBASE=`.

Hardware facts in the docs come from a **separate, private research repo**.
That repo is not a dependency of anything here and must never become one.

## Hard rules

1. **This repo ships nothing of BirdDog's.** No firmware, no binaries, no keys,
   no decrypted vendor payloads, and no material derived from any of them.
   companion-play replaces the device's operating system; it does not modify,
   repackage or redistribute the vendor's software. Nothing about building or
   using it requires a vendor file. **Do not add a feature that would change
   that** — it is the reason this repo can be public.
2. **Never commit Companion's bytes.** The release tarball and the offline
   module bundle are Bitfocus's to distribute. This repo pins versions in
   `build/config.sh` and downloads at build time; `vendor/` is gitignored and
   stays that way.
3. **A built image redistributes other people's code, and that is a different
   obligation.** Only licences on `CP_LICENCE_ALLOW` may ship;
   `build/filter-modules.mjs` enforces it and **fails the build** on a module
   that declares no licence. Do not relax it to "probably fine" — undeclared is
   not permissive. `ATTRIBUTIONS.md` and the generated
   `/usr/share/doc/companion-play/modules.tsv` are what makes it checkable.
4. **Never break the way back.** Only `boot` (p4) and `rootfs` (p8) are
   replaced. `uboot`, `trust`, `misc` and `recovery` stay stock so Rockchip
   recovery mode and the vendor recovery partition both survive. Dump a unit
   before taking it — factory recovery restores factory state, not that unit's
   provisioned serial, hostname or `/userdata`.
5. **`armbian_unlock_login` runs after the LAST `apt-get install`.** apt can
   reinstate Armbian's first-login gate, and a gate that comes back produces an
   image that boots, answers ping and lets nobody in. `03-make-image.sh` asserts
   on the finished image; keep that assertion below every install.
6. **Companion's state is not on the rootfs.** `/var/lib/companion-play` is the
   service account's home and is mounted from `userdata` (p9) on an installed
   unit, so reflashing the rootfs does not destroy an operator's configuration.
   Anything that writes operator data to the rootfs is a bug.
7. **There is no build step, and there must not be one.** Companion's
   `linux-arm64` tarball ships its own Node runtimes and native prebuilds. If
   something appears to need `npm install` or a compiler, the diagnosis is
   wrong — check `docs/02-verification.md` first.
8. **Do not reach for `chromium --kiosk`.** The display exists so an operator
   can keep the admin UI and web-button pages open as tabs. Kiosk mode removes
   the tab strip and blocks the fullscreen toggle.
9. **2 GB of RAM is the budget, and it is the real constraint.** Companion idles
   at ~509 MB with zero connections, and every connection is another Node child
   process. Measure before promising anyone a connection count.
10. **The default password is a property of a *published* image only.** Clearing
    `CP_DEFAULT_PASSWORD` and supplying a key must keep working, because that is
    what a unit on a show network should be built with. Never make the password
    path the only path.

## Test hardware

One PLAY is provisioned and reachable on the author's network, running **stock
firmware**. It is the reference for how the hardware behaves and is not to be
reflashed without saying so.

The build host is a shared aarch64 `tart` VM. It is shared with two other
appliance projects — check for concurrent activity (`losetup -a`, running
builds) before doing anything destructive, and only detach loop devices you
attached.

## Conventions

- Shell for the build; the appliance carries no compiled code of ours. The one
  exception is `build/filter-modules.mjs`, which runs under the *target's*
  bundled Node inside the chroot rather than adding a runtime to the host.
- Notes go in `docs/`, numbered: what was established, what it cost, and what is
  still assumed. **A claim with no command behind it is labelled as an
  assumption.** This project has far more of those than it has facts, and the
  docs are honest about which is which — keep them that way.

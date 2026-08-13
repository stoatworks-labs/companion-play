# 01 — Design

## The shape of the thing

A BirdDog PLAY with its firmware replaced, running Bitfocus Companion as the
whole product. HDMI drives a monitor showing Companion's own web UI; the USB-A
port takes a hub with a keyboard, mouse, touchscreen and Stream Decks; the
Ethernet port is Companion's network. Nothing of BirdDog's userspace survives,
and nothing of it is needed.

## Why this is mostly assembly, not engineering

Three things collapsed the work before it started, and it is worth recording
which, because each removes a category of risk rather than a task.

**The base OS matches.** Companion Pi 5.0.3 is Debian 13 trixie; `playbase`'s
pinned Armbian `renegade` image is also trixie. Same glibc, same sonames. There
is no cross-distro compatibility surface at all.

**Companion's Linux build is self-contained.** It ships its own Node runtimes
(18/22/26, aarch64) and its own native prebuilds for `node-hid`, `midi` and the
image codecs. The install is one `tar -xzf` of the tarball's `resources`
directory. Nothing compiles, on the build host or the target.

**The offline module bundle is already in the right shape.** It unpacks to 811
directories of the form `<module>/companion/manifest.json`, which is exactly what
Companion's `--extra-module-path` consumes. So the 811 modules are an untar too
— no web UI import, no network, and the unit is fully useful the first time it
boots on an isolated show network.

What remains is genuinely ours: the display, the two-mode switch, the install
model, and making 2 GB of RAM go far enough.

## Layout on disk

| Path | What | Where it lives |
|---|---|---|
| `/opt/companion` | the release, 588 MB | rootfs (p8) |
| `/opt/companion-modules` | the offline bundle, 459 MB | rootfs (p8) |
| `/etc/companion/config.yaml` | generated launch config | rootfs (p8) |
| `/var/lib/companion-play` | **operator state** — config, database, logs, user modules | `userdata` (p9) |
| `/var/lib/companion-play-kiosk` | Chromium profile | rootfs (p8) |

The split is the important part. The PLAY's `rootfs` partition is a fixed
**3.5 GiB** and the build fills **3.12 GiB** of it (measured, not estimated —
the first build came out at 3.47 GiB and did *not* fit until apt's leftovers
were cleaned; see `docs/02-verification.md`). `userdata` grows to the end of the
eMMC. Putting Companion's mutable state there does two things at once: it
removes the growth risk from the partition that cannot grow, and it means
**reflashing the rootfs to upgrade Companion does not wipe an operator's
configuration.** For an appliance that is worth more than the space.

Headroom on p8 is about **280 MB**, which is not much. If the base ever grows,
`/opt/companion-modules` (458 MB) moves to `userdata` too.

`/var/lib/companion-play` is the service account's *home directory*, which is
all that is needed to move Companion's state: Companion derives
`$HOME/.config/companion-nodejs` from it, and `companion-sync-udev-rules` reads
the home out of `passwd`.

## Users

Two accounts, and they never overlap.

`companion` is the service account, named to match companion-pi so that
project's documentation and scripts apply here unchanged. It is a system
account with no shell, and its only root privilege is the sudoers line
Companion needs to install the surface udev rules it generates at runtime, plus
power control.

`cplay` is the human, in `sudo`. It also owns the X session, because the display
is a user session and running a browser as a service account with USB privileges
is not a trade worth making.

How `cplay` authenticates depends on who the image is for, and both paths must
keep working. A **published** image ships a documented default password, because
that is the only thing that makes a downloaded image usable by anyone but its
builder. A **private** build clears `CP_DEFAULT_PASSWORD`, supplies
`secrets/authorized_keys`, and gets a key-only account with the password locked
— which is what a unit going on a show network should have.

## The display

X, openbox, Chromium. Not Wayland, not `cog`, not `chromium --kiosk`.

The operator asked for tabs, a keyboard and a mouse, which rules out kiosk mode
— it removes the tab strip and blocks the fullscreen toggle. Once there are
real windows, dialogs and a fullscreen toggle, there has to be a window manager
to grant them; openbox is the smallest thing that does. `weblinked-os` already
established that a bare X server comes up on this hardware, so the base is not
new ground; the window manager is the only addition.

Chromium's GPU path is **off by default**. The PLAY's Mali-450 is GLES2-only and
on a mainline kernel is driven by Lima, and a DOM-only UI gains nothing from it.
More to the point, a broken GL stack on this class of hardware presents as a
blank window rather than an error, which is an expensive thing to debug on a
device with no serial console. `KIOSK_GPU=on` in `/etc/companion-play/kiosk.conf`
turns it on to test.

> The "no browser on the PLAY" ruling from earlier research on this hardware
> does **not** apply here. That was about a browser software-decoding 4K H.264
> while the VPU idled. Companion's UI decodes nothing, so the GLES2 ceiling is
> irrelevant to it. Check whether a conclusion depends on the video path before
> reusing it — this one does.

## Two modes

`companion-play-mode server|satellite`. Both drive the same surfaces over the
same single USB port, so they are mutually exclusive, and the switch enables one
unit while disabling the other rather than leaving that to systemd to race.

In satellite mode the display is disabled rather than pointed somewhere useless
— there is no local web UI to show.

Satellite is **scaffolded, not verified**: the mode script refuses to switch
unless the binary is actually present, because enabling a unit whose `ExecStart`
does not exist would stop the server and start nothing, and the unit would go
dark with no obvious cause.

## What this costs

The unit stops being an NDI/SRT decoder, and the vendor's web UI goes with it —
along with any fleet tooling that drives PLAYs through that UI. Both are
recoverable by reflashing from the factory image, which is why "never break the
way back" is a hard rule in `AGENTS.md` rather than a preference.

## The constraint that decides everything

**2 GB of RAM.** Companion idles at ~509 MB with no connections configured, and
every connection is another Node child process in the ~70–100 MB band. Chromium
with two tabs will want several hundred more. The arithmetic is tight enough
that a connection count should not be promised to anyone until it has been
measured — see the open questions in `docs/02-verification.md`.

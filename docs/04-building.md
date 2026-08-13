# 04 — Building

## Host

**aarch64 Linux, as root.** The chroot runs the target's own binaries directly —
including Companion's bundled Node, which is how `config-tool.js` can generate
the image's config at build time. No `qemu-user-static`, no binfmt registration,
nothing to go wrong in emulation.

This Mac has no container runtime, but it has `tart`. The shared VM is
`wlos-build`, already provisioned for `weblinked-os` and `polecat`:

```bash
tart ip wlos-build --resolver=arp
```

> Clones of a `tart` base image share a MAC, so an ARP answer can be stale — see
> `reference_vm_subnet_shadowing`. Confirm with `ssh admin@<ip> hostname`.

**The VM is shared with two other appliance projects.** Before anything
destructive, check `losetup -a` and running builds, and only detach loop devices
you attached yourself.

Host packages:

```bash
sudo apt-get install -y rsync cloud-guest-utils e2fsprogs xz-utils curl
```

## Inputs

Two things the build needs that are not in the repo:

1. **`secrets/authorized_keys`** — at least one public key. `03-make-image.sh`
   refuses to build without it, because an appliance with no key in it and no
   console password is a brick.
2. **`vendor/companion-offline-module-bundle-<version>-<build>.tar.gz`** — there
   is no public API for bundles; download it from a running Companion of the
   pinned version (Modules → offline bundle). `02-fetch-companion.sh` will pick
   it up out of `~/Downloads` automatically if it is there.

The Companion release tarball itself is fetched automatically and pinned in
`build/config.sh`.

## Running it

```bash
ssh -n admin@<vm-ip> 'cd ~/companion-play && setsid sudo build/mk > build.log 2>&1 < /dev/null &'
```

`setsid` and the redirections matter — a plain `nohup … &` over SSH keeps the
session open and a dropped connection takes the build with it.

Steps run individually too:

| Step | Root? | Network? | What |
|---|---|---|---|
| `01-fetch-base.sh` | no | yes | the pinned Armbian image |
| `02-fetch-companion.sh` | no | yes | Companion tarball + stage the bundle |
| `03-make-image.sh` | **yes** | yes (apt) | everything else |

02 is separate on purpose: a chroot failure in 03 should not cost a 600 MB
re-download.

## Bumping Companion

Query the same API companion-pi uses, then update all three lines in
`build/config.sh` together:

```bash
curl -s 'https://api.bitfocus.io/v1/product/companion/packages?branch=stable&limit=3&target=linux-arm64-tgz'
```

**Download the matching offline module bundle at the same time.** Bitfocus
publish the two as a matched pair sharing a build id, and
`02-fetch-companion.sh` checks that the bundle in `vendor/` carries the id in
`config.sh`. A bundle from a different build will mostly work, which is worse
than failing.

## Assertions the build makes, and why each exists

None of these are decoration; each covers a failure that produces a *working-
looking* image.

- **`*/resources/main.js` in the tarball.** The install extracts
  `--wildcards '*/resources'`. If that pattern stops matching, the extract
  succeeds, `/opt/companion` is empty, and the unit boots into a service that
  exits immediately.
- **`*/companion/manifest.json` in the bundle**, and **more than 100 modules
  extracted**. A format change would give an image with zero modules and no
  error anywhere.
- **The chroot root is populated** (`[ -d $ROOT/etc ]`) before anything else. A
  mount that failed silently leaves an empty directory against which every later
  `[ ! -e … ]` check trivially passes — a first attempt at testing chroot
  helpers elsewhere in this fleet reported success while running nothing at all.
- **No first-login gate in the finished image.** Armbian minimal blocks every
  login until a password is set at the console, which on a headless appliance is
  indistinguishable from an unbootable brick. The obvious fix is a no-op — the
  `armbian-firstlogin.service` unit does not exist on 26.8.1 renegade
  trixie/minimal — so the check is on the paths that actually gate login, run on
  the product rather than the base.
- **`config.yaml` is non-empty.** Silent failure of `config-tool init` would
  leave `launch.sh`'s `source <(… generate)` producing nothing, and Companion
  would start on defaults with no `--extra-module-path` — i.e. with none of the
  811 modules.

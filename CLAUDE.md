# CLAUDE.md — command reference

Read [AGENTS.md](AGENTS.md) first — it explains the model and the rules. This
file is just the commands.

## Build

Requires an **aarch64 Linux host, as root** — the build runs the target's own
binaries in a chroot, including Companion's bundled Node. On Apple Silicon a
`tart` VM is that host.

```bash
tart run wlos-build --no-graphics &
VM=$(tart ip wlos-build --resolver=arp)

rsync -a --exclude work/ --exclude out/ --exclude cache/ --exclude .git/ \
  ~/Projects/companion-play/ admin@$VM:~/companion-play/

ssh -n admin@$VM 'cd ~/companion-play && setsid sudo build/mk > build.log 2>&1 < /dev/null &'
ssh -n admin@$VM 'tail -f ~/companion-play/build.log'
```

`setsid` and the redirections matter — a plain `nohup … &` over SSH keeps the
session open, so a dropped connection takes the build with it.

Stages are individually re-runnable:

```bash
build/01-fetch-base.sh          # no root, network
build/02-fetch-companion.sh     # no root, network
sudo build/03-make-image.sh     # root, chroot
```

## What you must supply

| Path | Why |
|---|---|
| `vendor/companion-offline-module-bundle-<version>-<build>.tar.gz` | no public API for bundles — download it from your own Companion's Modules page. Picked up from `~/Downloads` automatically. |
| `secrets/authorized_keys` | only for a key-only build (`CP_DEFAULT_PASSWORD` cleared). Optional otherwise. |

## Checks that run anywhere

```bash
bash -n build/*.sh overlay/usr/local/bin/* overlay/usr/local/sbin/*
shellcheck -S warning build/mk build/*.sh overlay/usr/local/bin/* overlay/usr/local/sbin/*
node build/filter-modules.mjs <moduleDir> "MIT,ISC" /tmp/report.tsv
```

## Bumping Companion

```bash
curl -s 'https://api.bitfocus.io/v1/product/companion/packages?branch=stable&limit=3&target=linux-arm64-tgz'
```

Update `COMPANION_VERSION`, `COMPANION_BUILD` and `COMPANION_TARBALL` in
`build/config.sh` **together**, and download the matching offline module bundle
at the same time — they are published as a matched pair sharing a build id, and
`02-fetch-companion.sh` checks it.

## House rules

- Shell for the build. The one exception is `build/filter-modules.mjs`, which
  runs under the *target's* Node inside the chroot rather than adding a runtime
  to the build host.
- Never commit Companion's bytes, and never add anything that would require a
  BirdDog file to build or run — that is why this repo can be public.
- Label assumptions as assumptions in `docs/`. Most of this project is still
  assumption, and the docs say so deliberately.

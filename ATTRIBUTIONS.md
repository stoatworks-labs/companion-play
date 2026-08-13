# Attributions

This repository contains build scripts and configuration. It contains no
third-party code — every artifact is downloaded at build time and none of it is
committed here.

A **built image**, however, redistributes several other people's work. What
follows applies to anyone flashing or passing on an image, and the same notices
are installed at `/usr/share/doc/companion-play/` inside it.

## Bitfocus Companion

<https://github.com/bitfocus/companion>

Copyright (c) 2018 Bitfocus AS — William Viker & Håkon Nessjøen.
Licensed under the **MIT License** (Part 1 of the project's `LICENSE.md`; Part 2
is a contributor agreement and Part 3 lists Companion's own bundled
dependencies).

The image ships the official `linux-arm64` release unmodified, extracted to
`/opt/companion`. Companion's full licence text travels with it at
`/usr/share/doc/companion-play/companion-LICENSE.md`.

Companion also bundles its own Node.js runtimes and native prebuilds; their
licences are covered by Part 3 of the file above.

**companion-play is not a Bitfocus product and is not affiliated with or
endorsed by Bitfocus AS.** "Companion" and "Bitfocus" are theirs. This project
packages their software for a particular piece of hardware; support questions
about Companion itself belong with Bitfocus, and bugs seen here should be
reproduced on a supported platform before being reported to them.

## Companion modules

The image includes modules from Bitfocus's official offline module bundle. Each
is separately copyrighted by its own authors and separately licensed.

Because an image *redistributes* these — as opposed to an operator downloading
the bundle themselves — the build enforces a licence policy: only modules
declaring a licence on the allow-list in `build/config.sh` are included, and
`build/filter-modules.mjs` deletes the rest.

Measured on the 5.0.3 bundle, all 811 modules declared a licence in their
manifest: **799 MIT, 9 ISC, 3 LGPL-3.0**. The three LGPL-3.0 modules
(`cleartouch-ippctrl`, `pnh-opencountdown`, `pnh-soundr`) are **not shipped**.
They are perfectly good modules; weak copyleft simply carries a source-offer
obligation that an appliance image is the wrong place to satisfy. Install them
from a bundle downloaded from your own Companion, where nobody is
redistributing anything on anyone's behalf.

**Every module in an image is listed, with its version and declared licence, at
`/usr/share/doc/companion-play/modules.tsv`.** That file is generated at build
time from the modules actually present, so it cannot drift from what shipped.
It is also attached to each release.

## Armbian

<https://www.armbian.com/>

The base OS is an unmodified Armbian `renegade` minimal image, pinned by
checksum. Armbian is a Debian derivative; its components carry their own
licences, predominantly GPL. Nothing in this repository modifies Armbian's
sources — the build adds packages from Debian's archives and writes
configuration.

## Debian

Packages installed into the image come from Debian's own archives under their
respective licences. The image is a Debian derivative in the ordinary sense and
carries Debian's copyright files at their usual locations.

## BirdDog

<https://birddog.tv/>

"BirdDog" and "PLAY" are BirdDog's trademarks, used here only to identify the
hardware this software runs on. **companion-play is not a BirdDog product and is
not affiliated with or endorsed by BirdDog.**

This project ships **no BirdDog code, firmware, keys or binaries**, and none is
required to build or use it. It replaces the device's operating system with
Armbian; it does not modify, repackage or redistribute the vendor's firmware.

Installing it will void your warranty, remove BirdDog's software including the
NDI and SRT decoding the device was sold to do, and is entirely at your own
risk. See the README.

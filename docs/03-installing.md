# 03 — Installing

**Nothing here has been done on hardware.** The partition facts are measured
(from prior research on this hardware, and from a sibling appliance project); the procedure is not.

## The two-partition rule

| # | Name | Size | companion-play |
|---|---|---|---|
| p1 | `uboot` | 4 MiB | leave |
| p2 | `trust` | 4 MiB | leave |
| p3 | `misc` | 4 MiB | leave |
| p4 | `boot` | 64 MiB | **replace** |
| p5 | `recovery` | 64 MiB | leave |
| p6 | `backup` | 32 MiB | leave |
| p7 | `oem` | 64 MiB | leave |
| p8 | `rootfs` | **3.5 GiB** | **replace** |
| p9 | `userdata` | grows to end of eMMC | **ours — Companion's state** |

Because `uboot`, `trust`, `misc` and `recovery` are untouched, **Rockchip
recovery mode and the vendor recovery partition both survive an install.** That
is the property that makes this defensible on hardware bought in quantity, and
it is why the rootfs image is written into p8 rather than the disk being
repartitioned.

eMMC is `mmcblk1`.

## Try microSD first — if the slot is fitted

Still the open question, inherited unchanged from `polecat` and `weblinked-os`:
the `sdmmc` controller probes and `vcc_sd` supplies 3.3 V, but nobody has
confirmed a physical slot. **Insert any microSD and look for `mmcblk0`.**

If it is fitted, `build/mk` already produces exactly what is needed — a
whole-disk image with its own partition table and u-boot in the gap. Write it to
a card, boot, and eMMC is untouched: card in is companion-play, card out is a
stock PLAY. Every experiment becomes reversible by pulling the card, which is
worth a great deal on a device with no confirmed serial console.

## The eMMC path

Not built yet. The shape, from `polecat`:

1. Dump the unit first. Factory recovery restores *factory* state, not this
   unit's provisioned serial, hostname or `/userdata`.
2. Build a `boot` (Android boot image: kernel + Rockchip `resource.img`
   carrying the DTB) and a `rootfs` ext4 image sized for p8.
3. `dd` both into place over SSH and reboot. No case opening, no USB, no
   recovery dance.

`rootfs` must fit **3.5 GiB**. The build currently uses roughly 2.6–2.7 GB
(see `docs/02-verification.md`), so it fits, but the headroom is not large —
which is the reason for the next section.

## Companion's state goes on `userdata`

`/var/lib/companion-play` is the `companion` service account's home, and on an
installed unit it is p9 rather than a rootfs directory:

```
/dev/mmcblk1p9  /var/lib/companion-play  ext4  defaults,nofail  0 2
```

`nofail` is deliberate: on a microSD build there is no p9, and the same image
must boot either way rather than dropping to an emergency shell.

Two things follow, and both are the point:

- The 3.5 GiB rootfs never grows. Companion's database, logs and any modules an
  operator installs land on the partition that has room.
- **Upgrading Companion is a rootfs reflash that preserves configuration.**
  Write a new p8, reboot, and the operator's buttons, connections and surfaces
  are exactly where they were.

The vendor's `/userdata` contents are not preserved by this. Anything of
BirdDog's on p9 is gone once it is reformatted, so dump it with the rest of the
unit before starting.

## Getting back to stock

Rockchip recovery mode with the vendor's factory image, which is an `RKFW`
container wrapping an `RKAF` — readable with Rockchip's own tooling. This
restores the whole device, including the partitions left untouched above.

It restores **factory** state, not this unit's provisioned identity: its serial,
hostname and `/userdata` do not come back. Dump a unit before you take it.

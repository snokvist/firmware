# Hi3516CV610 NOR boot: image anatomy, the GSL defect, and the tools here

Status 2026-07-30. Everything below was established on real hardware (K662C6S module:
Hi3516CV610 + IMX662, 16 MB SPI-NOR, 128 MB DDR3, u-boot DDR variant `20s`) plus binary
analysis of the OpenIPC prebuilt against a factory flash dump of the same board.

## Boot image anatomy (fixed offsets, 16 MB NOR)

```
0x00000            boot header (key/info areas, magic 0x3C7896E1)
0x00C00 - 0x05778  GSL: DDR training code + handoff loader
                   = image_tool/input/gsl.bin in OpenIPC/u-boot-hi3516cv6xx
0x05772 - 0x09440  reginfo (per-board DDR table, from reginfo/*.bin) + handoff metadata:
                     0x9024 / 0x9080  byte length of the u-boot stage
                     0x9088           its load address (0x41700000)
0x09400            u-boot area input starts here (image_tool packs it verbatim)
0x09440            [load][entry] header, then u-boot start.S ("System startup" is
                   u-boot's own banner), then hw_compressed startup: the SoC's hardware
                   gzip engine (regs 0x170Fxxxx) inflates the main U-Boot 2022.07
                   image to 0x41800000 and jumps
0x40000            u-boot environment (CONFIG_ENV_OFFSET, size 0x10000)
0x50000            firmware.bin (fitImage, rootfs.squashfs at the next 64 KB boundary)
```

The boot chain is mask ROM -> GSL -> u-boot -> kernel. The GSL must run before DDR
exists; it is a proprietary HiSilicon blob on every HiSi platform (u-boot cannot replace
it because u-boot runs from DDR).

## The defect (fixed upstream in OpenIPC/u-boot-hi3516cv6xx PR #6)

OpenIPC's prebuilt `boot-hi3516cv610-*-nor.bin` hangs on real silicon immediately after
the DDR boot-table print. Root cause: the vendored `gsl.bin` (SDK 1.0.2.0 import) has
DDR training code that hangs on real chips; it was only ever exercised by the QEMU smoke
gate, which bypasses the DDR stage. The reginfo tables, image_tool packing, and u-boot
itself are all correct. Fix: swap in the newer GSL (`ddr param version 20250416`)
extracted from a factory device — see the PR for the verification chain.

Two subtleties, learned the hard way, encoded in `mksplicedboot.sh`:

- The u-boot stage begins at 0x9440 with its own `[load][entry]` header. Splicing at
  0x9480 (where the byte streams happen to re-converge) pairs one image's entry pointer
  with the other's code: silent hang after the DDR prints.
- The stage length words at 0x9024/0x9080 must match the u-boot donor. A stale shorter
  length truncates the copy to RAM, lopping `.rodata`/`.data` off the end (they sit
  after the ~190 KB gzip payload): u-boot then "prints" a few hundred bytes of
  uninitialized DDR — perfectly framed random bytes at 115200 baud — and dies during
  decompression.

## Tools

- `mksplicedboot.sh` — grafts a known-good GSL + reginfo (e.g. from a vendor flash dump,
  bytes 0..0x9440) onto an OpenIPC u-boot stage, patching the length words. Defaults
  produce the configuration verified to boot Linux on the K662C6S. The current
  u-boot-hi3516cv6xx tree already carries the fixed gsl.bin, so splicing is only
  needed for older or vendor boot dumps.
- `mkfullimage.sh` — assembles a complete externally-flashable 16 MB NOR image from a
  boot binary + `firmware.bin` (post-image.sh only emits the sysupgrade payload, which
  contains no bootloader). Populates the environment (mandatory: this u-boot has no
  compiled-in bootcmd/bootargs), derives the kernel partition size from the FIT header,
  and includes the three settings this board needs: `init=/init`, `totalmem=128M` /
  `osmem=64M`, and a kernel partition large enough for the fitImage.

For the waybeam_lite-ng build, the top-level Makefile keeps this separation explicit:

```
make BOARD=hi3516cv6xx_waybeam_lite_ng TARGET=output-waybeam-ng UBOOT=../u-boot-hi3516cv6xx/output/boot-hi3516cv610-20s-nor.bin fullimage
```

fullimage rejects a pre-fix boot blob by checking for the fixed GSL marker, and
defaults the U-Boot environment to totalmem=128M, osmem=64M, mem=64M, and
init=/init.

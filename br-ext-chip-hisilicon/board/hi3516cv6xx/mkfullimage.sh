#!/bin/bash
#
# Assemble a complete, externally-flashable NOR image for Hi3516CV6xx.
#
# post-image.sh only produces firmware.bin (fitImage + rootfs.squashfs) — that
# is what a running camera sysupgrades to, and it deliberately contains no
# bootloader. For a virgin flash (NeoProgrammer, CH341A, ...) you need
# u-boot + a populated environment in front of it, which is what this builds:
#
#   0x00000  u-boot
#   0x40000  environment (CONFIG_ENV_OFFSET / CONFIG_ENV_SIZE)
#   0x50000  firmware.bin  (fitImage, then rootfs.squashfs at the next 64K block)
#   ...      padded to --flash-size with 0xff
#
# The environment MUST be populated. The OpenIPC cv610 u-boot has no
# compiled-in bootcmd/bootargs (CONFIG_USE_BOOTARGS is off, it relies on
# distro_bootcmd), so a blank 0xff env yields a board that reaches the u-boot
# prompt and stops there — no kernel, no ethernet, looks bricked.
#
# Three settings here are load-bearing and were each learned the hard way on a
# SIP-K662C6S (CV610 + IMX662, 128 MB DDR3):
#
#   init=/init   general/overlay/init is what mounts jffs2 on rootfs_data and
#                pivots into an overlayfs root. For a block-device root the
#                kernel only ever tries /sbin/init, so without this the overlay
#                never runs and / stays read-only forever (dropbear then cannot
#                even generate a host key, so ssh fails at KEX).
#   totalmem/osmem  read by load_hisilicon to size the MMZ pool. Defaults are
#                64M/32M; on a 128 MB board that leaves 32 MB unused.
#   bootcmd read length must cover the whole kernel partition, and the mtdparts
#                kernel partition must be >= the fitImage.
#
set -eu

UBOOT=
FIRMWARE=
OUT=
FLASH_SIZE=16
TOTALMEM=128M
OSMEM=64M
CONSOLE=ttyAMA0,115200
SOC=hi3516cv610
ROOTFS_K=8192
KERNEL_K=

usage() {
	cat <<-EOF
	Usage: $0 --uboot <file> --firmware <file> --out <file> [options]

	  --uboot FILE      bootloader blob written at offset 0
	  --firmware FILE   firmware.bin.hi3516cv6xx from output/images
	  --out FILE        image to write
	  --flash-size MB   total NOR size, default ${FLASH_SIZE}
	  --totalmem SIZE   physical DDR, default ${TOTALMEM}
	  --osmem SIZE      slice given to Linux, rest becomes MMZ, default ${OSMEM}
	  --console SPEC    kernel console, default ${CONSOLE}
	  --soc NAME        board/soc env strings, default ${SOC}
	  --kernel-size K   kernel partition in KB. Derived from the fitImage by
	                    default, which is what you want for a fresh flash. Pass
	                    it explicitly to reproduce a layout a board is already
	                    running, so an image differs from it in one variable
	                    only; must be >= the fitImage.
	  --rootfs-size K   rootfs partition in KB, default ${ROOTFS_K}. Whatever is
	                    left after boot+kernel+rootfs becomes rootfs_data, the
	                    jffs2 overlay — shrink this to buy writable space, but
	                    only on an image you are flashing externally, since
	                    changing it invalidates in-place sysupgrades.

	Note: OpenIPC's published boot-hi3516cv610-*-nor.bin has been observed to
	hang before printing its banner on real silicon (it is built as a QEMU
	smoke-gate artifact). Until that is fixed, pass the board's own vendor
	u-boot, extracted from a full flash dump:
	  dd if=dump.bin of=vendor-uboot.bin bs=1 count=262144
	EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		--uboot) UBOOT=$2; shift 2 ;;
		--firmware) FIRMWARE=$2; shift 2 ;;
		--out) OUT=$2; shift 2 ;;
		--flash-size) FLASH_SIZE=$2; shift 2 ;;
		--totalmem) TOTALMEM=$2; shift 2 ;;
		--osmem) OSMEM=$2; shift 2 ;;
		--console) CONSOLE=$2; shift 2 ;;
		--soc) SOC=$2; shift 2 ;;
		--kernel-size) KERNEL_K=$2; shift 2 ;;
		--rootfs-size) ROOTFS_K=$2; shift 2 ;;
		-h|--help) usage; exit 0 ;;
		*) echo "unknown argument: $1" >&2; usage >&2; exit 1 ;;
	esac
done

if [ -z "${UBOOT}" ] || [ -z "${FIRMWARE}" ] || [ -z "${OUT}" ]; then
	usage >&2
	exit 1
fi
for f in "${UBOOT}" "${FIRMWARE}"; do
	[ -r "$f" ] || { echo "cannot read $f" >&2; exit 1; }
done

ENV_OFFSET=$((0x40000))
ENV_SIZE=$((0x10000))
FW_OFFSET=$((0x50000))
TOTAL=$((FLASH_SIZE * 1024 * 1024))

UBOOT_SIZE=$(stat -c%s "${UBOOT}")
FW_SIZE=$(stat -c%s "${FIRMWARE}")
[ "${UBOOT_SIZE}" -le "${ENV_OFFSET}" ] || { echo "u-boot (${UBOOT_SIZE}) overruns env at ${ENV_OFFSET}" >&2; exit 1; }
[ $((FW_OFFSET + FW_SIZE)) -le "${TOTAL}" ] || { echo "firmware overruns ${FLASH_SIZE} MB flash" >&2; exit 1; }

# Kernel partition sizing: the fitImage sits at the start of firmware.bin and
# post-image.sh aligns rootfs.squashfs to the next 64K erase block after it, so
# that alignment boundary is exactly where the kernel partition has to end.
FIT_SIZE=$(python3 - "${FIRMWARE}" <<-'EOF'
	import struct, sys
	with open(sys.argv[1], 'rb') as f:
	    hdr = f.read(8)
	assert hdr[:4] == b'\xd0\x0d\xfe\xed', 'firmware.bin does not start with a FIT image'
	print(struct.unpack('>I', hdr[4:8])[0])
EOF
)
ERASE=$((64 * 1024))
if [ -n "${KERNEL_K}" ]; then
	KERNEL_SIZE=$((KERNEL_K * 1024))
	[ $((KERNEL_SIZE % ERASE)) -eq 0 ] || { echo "--kernel-size ${KERNEL_K}K is not a multiple of the 64K erase block" >&2; exit 1; }
	[ "${KERNEL_SIZE}" -ge "${FIT_SIZE}" ] || { echo "--kernel-size ${KERNEL_K}K is smaller than the fitImage (${FIT_SIZE} bytes)" >&2; exit 1; }
	# post-image.sh aligns rootfs.squashfs to the first 64K block after the
	# fitImage, so an oversized kernel partition would swallow the start of the
	# rootfs unless we account for the gap.
	FIT_ALIGNED=$(( (FIT_SIZE + ERASE - 1) / ERASE * ERASE ))
	ROOTFS_SKEW=$((KERNEL_SIZE - FIT_ALIGNED))
else
	KERNEL_SIZE=$(( (FIT_SIZE + ERASE - 1) / ERASE * ERASE ))
	KERNEL_K=$((KERNEL_SIZE / 1024))
	ROOTFS_SKEW=0
fi
BOOT_K=$((FW_OFFSET / 1024))

MTDPARTS="sfc:${BOOT_K}K(boot),${KERNEL_K}K(kernel),${ROOTFS_K}K(rootfs),-(rootfs_data)"
BOOTARGS="mem=${OSMEM} console=${CONSOLE} clk_ignore_unused root=/dev/mtdblock2 rootfstype=squashfs ro init=/init mtdparts=${MTDPARTS}"
BOOTCMD=$(printf 'sf probe 0; sf read 0x41000000 0x%x 0x%x; bootm 0x41000000' "${FW_OFFSET}" "${KERNEL_SIZE}")

ROOTFS_SIZE=$((FW_SIZE - KERNEL_SIZE + ROOTFS_SKEW))
if [ "${ROOTFS_SIZE}" -gt $((ROOTFS_K * 1024)) ]; then
	echo "rootfs (${ROOTFS_SIZE} bytes) exceeds the ${ROOTFS_K}K rootfs partition" >&2
	exit 1
fi
if [ $((FW_OFFSET + KERNEL_SIZE + ROOTFS_SIZE)) -gt "${TOTAL}" ]; then
	echo "kernel + rootfs overrun the ${FLASH_SIZE} MB flash" >&2
	exit 1
fi

python3 - "${OUT}" "${UBOOT}" "${FIRMWARE}" "${TOTAL}" "${ENV_OFFSET}" "${ENV_SIZE}" "${FW_OFFSET}" \
	"${SOC}" "${TOTALMEM}" "${OSMEM}" "${BOOTCMD}" "${BOOTARGS}" "${ROOTFS_SKEW}" "${KERNEL_SIZE}" <<-'EOF'
	import struct, sys, zlib
	(out, uboot, firmware, total, env_off, env_size, fw_off,
	 soc, totalmem, osmem, bootcmd, bootargs, skew, kernel_size) = sys.argv[1:15]
	total, env_off, env_size, fw_off = int(total), int(env_off), int(env_size), int(fw_off)
	skew, kernel_size = int(skew), int(kernel_size)

	env = [
	    'arch=arm', 'cpu=armv7', 'baudrate=115200', 'ethact=eth0',
	    f'board={soc}', f'board_name={soc}', f'soc={soc}',
	    'bootdelay=3',
	    f'totalmem={totalmem}', f'osmem={osmem}',
	    f'bootcmd={bootcmd}', f'bootargs={bootargs}',
	]
	# u-boot env: 4-byte little-endian CRC32 over the body, then NUL-separated
	# var=val entries terminated by an empty entry, zero-padded to env_size.
	body = b''.join(v.encode() + b'\0' for v in env) + b'\0'
	if len(body) > env_size - 4:
	    sys.exit('environment does not fit in %d bytes' % env_size)
	body = body.ljust(env_size - 4, b'\0')
	blob = struct.pack('<I', zlib.crc32(body) & 0xffffffff) + body

	img = bytearray(b'\xff' * total)
	with open(uboot, 'rb') as f:
	    u = f.read()
	img[0:len(u)] = u
	img[env_off:env_off + env_size] = blob
	with open(firmware, 'rb') as f:
	    fw = f.read()
	if skew:
	    # The kernel partition was widened past where post-image.sh put the
	    # squashfs, so firmware.bin has to be split and the rootfs half pushed
	    # out to the real partition start.
	    split = kernel_size - skew
	    img[fw_off:fw_off + split] = fw[:split]
	    img[fw_off + kernel_size:fw_off + kernel_size + len(fw) - split] = fw[split:]
	else:
	    img[fw_off:fw_off + len(fw)] = fw
	with open(out, 'wb') as f:
	    f.write(img)
EOF

md5sum "${OUT}" > "${OUT}.md5"

cat <<-EOF
	Wrote ${OUT} (${FLASH_SIZE} MB)
	  u-boot    0x00000  ${UBOOT_SIZE} bytes
	  env       0x$(printf %05x ${ENV_OFFSET})  ${ENV_SIZE} bytes
	  firmware  0x$(printf %05x ${FW_OFFSET})  ${FW_SIZE} bytes (fitImage ${FIT_SIZE})
	  mtdparts  ${MTDPARTS}
	  bootargs  ${BOOTARGS}
EOF

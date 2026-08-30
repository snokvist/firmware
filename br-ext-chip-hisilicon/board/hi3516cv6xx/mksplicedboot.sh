#!/bin/bash
#
# Splice a HiSilicon CV6xx boot image: keep a known-good DDR stage from one
# image, take the u-boot from another.
#
# Why this exists
# ---------------
# OpenIPC's published boot-hi3516cv610-20s-nor.bin hangs on a SIP-K662C6S
# before printing a banner, while the board's own vendor u-boot boots fine.
# Diffing the two (2026-07-21) shows the images are FIXED-OFFSET SECTIONED and
# agree on every section boundary:
#
#   0x00000-0x00C90  boot header + entry stub      identical
#   0x00C90-0x05772  DDR training CODE             DIFFERS  (the two words at
#                                                  0x0C90 and 0x0CCC are this
#                                                  stage's own entry branch and
#                                                  end-of-code pointer)
#   0x05772-0x09480  DDR register table (reginfo)  identical (~15 KB; only the
#                                                  build timestamp at 0x6018
#                                                  and the training code's own
#                                                  message strings differ)
#   0x09480-EOF      stage-1 loader + gzip u-boot  differs (expected)
#
# So the earlier "image_tool packed the wrong reginfo" theory is wrong: the
# register table is byte-identical and names the right part,
# Hi3516CV610-DMEB_4L_DDR3_2133M_128MB_16bit-A7_950M_QFN.xlsm. What differs is
# the CODE that consumes it. The vendor's is newer ("ddr param version
# 20250416"); OpenIPC's carries "reg_bak error!" / "The table is incorrect."
# paths the vendor's does not have. That makes the training code the prime
# suspect for the pre-banner hang.
#
# This script tests that hypothesis directly: vendor DDR stage + OpenIPC u-boot.
# If the result boots, the defect is in OpenIPC's DDR training blob and the bug
# report writes itself. If it still hangs before the banner, the DDR stage is
# exonerated and the fault is in stage-1 / the decompressor.
#
# HARDWARE RESULT 2026-07-30 (final): with split 0x9440 AND the stage-1 length
# words (0x9024/0x9080) taken from the u-boot donor, the spliced image BOOTS
# ALL THE WAY to Linux userspace on the SIP-K662C6S. OpenIPC's u-boot itself
# is fine; only its DDR training blob is broken on real silicon. The defaults
# below produce that working configuration.
#
# Earlier attempt, kept for the record: splicing at 0x9480 hangs in the same
# place as stock. That test was VOID, not negative: the stage-1 section begins
# at 0x9440 with its own [load_addr][entry] header —
#
#   0x9440  load address  0x41700000        (same in both images)
#   0x9444  entry point   vendor 0x41700589 / OpenIPC 0x417006a8  (DIFFERS)
#   0x9448  first branch of stage-1 code    (DIFFERS)
#
# so a 0x9480 split pairs the vendor's entry pointer with OpenIPC's stage-1
# code and jumps into the middle of an unrelated function. The identical
# 0x9449-0x9480 run that motivated the 0x9480 split is just ARM mode/cache
# boilerplate that matches between the two builds. The correct boundary is
# 0x9440; the only bytes the vendor then donates are the boot header and DDR
# training code (0xC90-0x5772) plus 13 cosmetic reginfo bytes (timestamp).
#
set -eu

SPLIT=$((0x9440))
DDR=
UBOOT=
OUT=
PAD=262144

usage() {
	cat <<-EOF
	Usage: $0 --ddr <image> --uboot <image> --out <file> [options]

	  --ddr FILE     donor for the header + DDR training + reginfo sections;
	                 use a boot image known to bring this board's DDR up
	                 (e.g. the first 256 KB of a vendor flash dump)
	  --uboot FILE   donor for the stage-1 loader and compressed u-boot
	  --out FILE     spliced boot image to write
	  --split OFF    section boundary, default $(printf '0x%x' ${SPLIT})
	                 (0x9440 = start of the stage-1 [load,entry] header;
	                 0x9480 was tried 2026-07-30 and is WRONG, see header)
	  --pad BYTES    zero-pad the result to this size, default ${PAD}
	                 (matches the vendor image, whose u-boot region runs to the
	                 environment at 0x40000); 0 disables padding
	EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		--ddr) DDR=$2; shift 2 ;;
		--uboot) UBOOT=$2; shift 2 ;;
		--out) OUT=$2; shift 2 ;;
		--split) SPLIT=$(($2)); shift 2 ;;
		--pad) PAD=$(($2)); shift 2 ;;
		-h|--help) usage; exit 0 ;;
		*) echo "unknown argument: $1" >&2; usage >&2; exit 1 ;;
	esac
done

if [ -z "${DDR}" ] || [ -z "${UBOOT}" ] || [ -z "${OUT}" ]; then
	usage >&2
	exit 1
fi
for f in "${DDR}" "${UBOOT}"; do
	[ -r "$f" ] || { echo "cannot read $f" >&2; exit 1; }
done

python3 - "${DDR}" "${UBOOT}" "${OUT}" "${SPLIT}" "${PAD}" <<-'EOF'
	import sys
	ddr_f, ub_f, out, split, pad = sys.argv[1:6]
	split, pad = int(split), int(pad)

	ddr = open(ddr_f, 'rb').read()
	ub = open(ub_f, 'rb').read()
	for name, blob in ((ddr_f, ddr), (ub_f, ub)):
	    if blob[:4] != b'\xea\xff\x00\x00':
	        sys.exit('%s does not look like a CV6xx boot image '
	                 '(expected ea ff 00 00 at offset 0)' % name)
	    if len(blob) <= split:
	        sys.exit('%s is shorter than the split offset' % name)

	# Sanity: the two donors must agree on the boot header, otherwise they are
	# not the same image format and the fixed-offset assumption is void.
	if ddr[:0x0c90] != ub[:0x0c90]:
	    sys.exit('boot headers differ - donors are not the same image format')

	img = bytearray(ddr[:split] + ub[split:])
	# The reginfo region carries handoff metadata describing the NEXT stage:
	#   0x9024 / 0x9080  length of the stage-1 image the loader copies to RAM
	#   0x9088           its load address (0x41700000)
	# The length must describe the u-boot donor's payload, not the DDR donor's
	# (found 2026-07-30: a 13 KB shortfall here truncated .rodata/.data and
	# produced framed-random-bytes "banners" followed by a hang).
	for loff in (0x9024, 0x9080):
	    if loff + 4 <= split:
	        img[loff:loff+4] = ub[loff:loff+4]
	if pad:
	    if len(img) > pad:
	        sys.exit('spliced image (%d) exceeds the pad size (%d)' % (len(img), pad))
	    img = img.ljust(pad, b'\0')
	open(out, 'wb').write(img)

	# Report where the donors actually diverge, so a boundary that lands in the
	# middle of a section is obvious rather than silent.
	n = min(len(ddr), len(ub))
	first = next((i for i in range(split, n) if ddr[i] != ub[i]), None)
	last = next((i for i in range(split - 1, -1, -1) if ddr[i] != ub[i]), None)
	print('  last difference before split: 0x%05x' % (last if last is not None else -1))
	print('  first difference after split: 0x%05x' % (first if first is not None else -1))
	print('  wrote %s (%d bytes)' % (out, len(img)))
EOF

md5sum "${OUT}"

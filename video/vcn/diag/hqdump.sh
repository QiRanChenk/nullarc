#!/bin/bash
# hqdump.sh (root) [ring]: compute queue (ME 1 pipe 0 queue 0) hardware state next to the kext's view; "ring" also dumps the ring
P=/Users/Shared/gpu/phxctl/phxctl
N="ACTIVE VMID PQ_BASE PQ_BASE_HI PQ_RPTR DB_CTL PQ_CONTROL IB_BASE IB_BASE_HI IB_RPTR IB_CONTROL IQ_RPTR DEQ_REQ ERROR PQ_WPTR_LO PQ_WPTR_HI DEQ_STATUS"
$P wreg 0xa900 0x4 >/dev/null
V=$($P regs 0x320b 0x320c 0x3211 0x3212 0x3213 0x3218 0x321a 0x321b 0x321c 0x321d 0x321e 0x3220 0x3221 0x323c 0x323f 0x3240 0x3248 | awk '{print $NF}' | tr '\n' ' ')
$P wreg 0xa900 0x0 >/dev/null
set -- $V; o="hqd:"; for n in $N; do o="$o $n=$1"; shift; done; echo "$o"
echo "wb (rptr report +0, wptr +16): $($P vram 0x2541000 8 | tr '\n' ' ')"
echo "compute fence: $($P vram 0x2550000 2 | tr '\n' ' ') gfx fence: $($P vram 0x2580000 2 | tr '\n' ' ') $(sysctl -n debug.phxvcn_stat | grep -o 'seq 0x.*')"
[ "${1:-}" = ring ] && $P vram 0x2540000 256 && $P vram 0x2540400 256 && $P vram 0x2540800 256 && $P vram 0x2540c00 256
exit 0

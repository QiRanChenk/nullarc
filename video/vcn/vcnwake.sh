#!/bin/bash
# vcnwake.sh (root; called at the end of phxwake.sh after the GPU bring-up of a wake): VCN lost its power and its
# firmware with the rest of the GPU, and the kext forgot the ring (vcnForget). Bring it up again like at boot.
D=/Users/Shared/gpu/vcnup; P=/Users/Shared/gpu/phxctl/phxctl
[ -e $D/off ] && { echo "vcn: off ($D/off)"; exit 0; }
[ "$(sysctl -n debug.phxvcn 2>/dev/null)" = 1 ] && { echo "vcn: still adopted: nothing to do"; exit 0; }
# after a real power loss the register reads 0xffffffff and everything is redone (firmware included); when VCN was
# only powered down with the SMU message it stays readable and the bring-up starts at PowerUpVcn
v=$($P regs 0x7e02 | awk '{print $2}')
from=1; [ "$v" != "0xffffffff" ] && from=2
sysctl debug.phxmmvm=0 >/dev/null 2>&1
VCN_BOOT=1 FROM=$from bash $D/vcn_up.sh --run > $D/wake.log 2>&1; rc=$?
if [ $rc = 0 ] && grep -q '^M1 PASS' $D/wake.log; then
  sysctl debug.phxvcn=1 debug.phxmmvm=1 | tr '\n' ' '; echo "vcn: up again"
else
  echo "vcn: bring-up after the wake failed (rc $rc): $(tail -1 $D/wake.log)"
fi

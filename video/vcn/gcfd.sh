#!/bin/bash
# gcfd.sh: give the GC hub a protection-fault default page (the kext's wired MMHUB dummy page) and the ENABLE_DEFAULT bits
P() { /Users/Shared/gpu/phxctl/phxctl "$@"; }
P regs 0x2824 0x2828 0x2829 0x282a 0x282b 0x282c 0x1a70f 0x1a710 0x2004 | tr "\n" " "; echo
LO=$(P regs 0x1a70f | awk '{print $NF}'); HI=$(P regs 0x1a710 | awk '{print $NF}')
echo "dummy page >> 12 = $HI:$LO"
[ -n "$LO" ] && [ "$LO" != 0x00000000 ] || { echo "no dummy page (debug.phxmmvm=1 first)"; exit 1; }
P wreg 0x282b $LO | tail -1; P wreg 0x282c $HI | tail -1; P wreg 0x2824 0x1ffe | tail -1; P wreg 0x291c 0x00f80001 | tail -1
sleep 1; P regs 0x2824 0x2828 0x282b 0x2004 0x21a0 | tr "\n" " "; echo

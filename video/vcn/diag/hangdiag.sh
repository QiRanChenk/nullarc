#!/bin/bash
# hangdiag.sh: watches debug.phx_hang_kills; when it changes, dumps the GPU state once per second for 6 s into
# /Users/Shared/gpu/vcnup/hangdiag.log (synced), so the data survives a reboot.
L=/Users/Shared/gpu/vcnup/hangdiag.log; P=/Users/Shared/gpu/phxctl/phxctl
R="0x2004 0x2002 0x21a0 0x219f 0x219d 0x219e 0x219c 0x2084 0x2085 0x2086 0x2087 0x2088 0x2089 0x2824 0x2828 0x2829 0x282a 0x30e0 0x30e1 0x30e8 0x30f1 0x320b 0x320c 0x3213 0x321b 0x321c 0x321d 0xc0cc 0xc0cd 0xc0ce"
k0=$(sysctl -n debug.phx_hang_kills); echo "$(date '+%F %T') start kills $k0" >> $L; sync
while :; do
  k=$(sysctl -n debug.phx_hang_kills)
  if [ "$k" != "$k0" ]; then
    for i in 1 2 3 4 5 6; do
      { echo "== $(date '+%T') kills $k"; dmesg | grep -o -E "PhxBringup: [^\[]{0,200}" | grep -v gfxoff | tail -4
        $P regs $R | tr '\n' ' '; echo; sysctl -n debug.phxvcn_stat debug.phx_gcfault_stat
        [ $i = 1 ] && bash /Users/Shared/gpu/vcnup/hqdump.sh ring; } >> $L 2>&1
      sync; sleep 1
    done
    k0=$(sysctl -n debug.phx_hang_kills)
  fi
  sleep 0.3
done

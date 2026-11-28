#!/bin/bash
# vcnwatch.sh (root): when the VCN ring stands still with work in it for over a second, dump its state once per stall
# into /Users/Shared/gpu/vcnup/stall.log (registers twice, the ring frame at RPTR, fw_shared, the MMHUB and GC fault
# state, pm state, the kernel log of the seconds before). It also writes one line per 10 minutes with the submit
# count, so stalls can be counted per hour of decoding. Off: touch /Users/Shared/gpu/vcnup/watch-off
D=/Users/Shared/gpu/vcnup; P=/Users/Shared/gpu/phxctl/phxctl; L=$D/stall.log; last=""; n=0; dumped=0; t0=0; hb=0
R="0x7e02 0x7e01 0x7f43 0x7eac 0x7ead 0x7e85 0x7ee1 0x7f96 0x7e72"
[ -e $D/watch-off ] && exit 0
echo "## $(date '+%F %T') vcnwatch start" >> $L
while :; do
  s=$(sysctl -n debug.phxvcn_stat 2>/dev/null); now=$(date +%s)
  case "$s" in "vcn 1 "*) ;; *) sleep 5; continue;; esac
  r=$(echo "$s" | sed -E 's/.*RPTR (0x[0-9a-f]+) WPTR (0x[0-9a-f]+).*/\1 \2/')
  set -- $r
  if [ "$1" != "$2" ] && [ "$r" = "$last" ]; then n=$((n+1)); else n=0; fi
  if [ $dumped = 1 ] && [ "$r" != "$last" ]; then
    echo "   moved again $(date '+%T') after about $(( now - t0 + 1 )) s (RPTR $1 WPTR $2)" >> $L; dumped=0
  fi
  last=$r
  if [ $n -ge 4 ] && [ $dumped = 0 ]; then
    dumped=1; t0=$now
    { echo "== $(date '+%F %T') ring standing at RPTR $1 WPTR $2"; echo "$s"
      $P regs $R | tr '\n' ' '; echo
      sysctl -n debug.phxmmvm_stat debug.phx_gcfault_stat
      echo "pm: gfxoff $(sysctl -n debug.phx_pm_gfxoff) state $(sysctl -n debug.phx_pm_gfxoff_state) wakes $(sysctl -n debug.phx_pm_gfx_wakes) gfxclk $(sysctl -n debug.phx_pm_gfxclk) socclk $(sysctl -n debug.phx_pm_socclk) fclk $(sysctl -n debug.phx_pm_fclk_avg) memclk $(sysctl -n debug.phx_pm_memclk) busy $(sysctl -n debug.phx_pm_busy) socket $(sysctl -n debug.phx_pm_socket_mw) frames $(sysctl -n debug.nvaccel_iop_ok)"
      echo "ring at RPTR:"; $P vram $(printf '0x%x' $(( 0x4a00000 + ($1) * 4 ))) 32
      echo "fw_shared:"; $P vram 0x4ab0000 40
      echo "regs again:"; $P regs $R | tr '\n' ' '; echo
      ps axo pcpu,pid,comm | sort -rn | head -6
      echo "kernel log, last 8 s:"
      /usr/bin/log show --last 8s --style compact --predicate 'processID == 0' 2>/dev/null | tail -40 | cut -c1-220
      echo "all logs, last 8 s (lines by process):"
      /usr/bin/log show --last 8s --style compact 2>/dev/null | awk 'NR>1{print $4}' | sed 's/\[.*//' | sort | uniq -c | sort -rn | head -12
    } >> $L 2>&1; sync
  fi
  if [ $(( now - hb )) -ge 600 ]; then
    hb=$now; echo "# $(date '+%F %T') $(echo "$s" | sed -E 's/.*(submits [0-9]+).*(longest pending [0-9]+ ms).*/\1; \2/'); stuck $(echo "$s" | sed -E 's/.*\(times ([0-9]+)\).*/\1/')" >> $L
  fi
  sleep 0.3
done

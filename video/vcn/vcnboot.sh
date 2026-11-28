#!/bin/bash
# vcnboot.sh (LaunchDaemon local.vcnboot, root): VCN up at boot, before the user's apps start.
# Waits for phxboot to claim the GPU in this boot, then vcn_up.sh --run, debug.phxvcn=1, debug.phxmmvm=1.
# Safety net as phxboot's: a marker is set before the bring-up and removed after it; a boot that finds the marker
# (the last bring-up hung or the machine went down in it) creates the kill switch $D/off and does nothing.
# Log /var/log/vcnboot.log. Off: touch /Users/Shared/gpu/vcnup/off (and remove it to turn it on again).
D=/Users/Shared/gpu/vcnup; LOG=/var/log/vcnboot.log; MARK=/var/db/vcnboot.pending
exec >> $LOG 2>&1
echo "== $(date '+%F %T') vcnboot"
[ -e $D/off ] && { echo "off ($D/off)"; exit 0; }
if [ -e $MARK ]; then
  echo "the previous bring-up did not finish: VCN stays off (remove $D/off to try again)"; touch $D/off; rm -f $MARK; exit 0
fi
bt=$(sysctl -n kern.boottime | sed -E 's/.* sec = ([0-9]+),.*/\1/')
ok=0
for i in $(seq 1 180); do
  n=$(grep -n '^== ' /var/log/phxboot.log 2>/dev/null | tail -1 | cut -d: -f1)
  if [ -n "$n" ]; then
    h=$(sed -n "${n}p" /var/log/phxboot.log | awk '{print $2" "$3}')
    hs=$(date -j -f '%Y-%m-%d %H:%M:%S' "$h" +%s 2>/dev/null || echo 0)
    if [ "$hs" -ge "$bt" ] && sed -n "${n},\$p" /var/log/phxboot.log | grep -q '^claim -> kr 0x0'; then ok=1; break; fi
  fi
  sleep 1
done
[ $ok = 1 ] || { echo "phxboot did not claim the GPU within 180 s: nothing done"; exit 0; }
# let phxboot hand the panel to WindowServer first ("armed and released", about a second after the claim; absent when
# WindowServer stays on the firmware framebuffer): the MMHUB mode change should not land in that window
for i in $(seq 1 25); do sed -n "${n},\$p" /var/log/phxboot.log | grep -q -E '^armed and released|^done' && break; sleep 1; done
sleep 2
[ "$(sysctl -n debug.phxvcn 2>/dev/null)" = 1 ] && { echo "VCN already adopted"; exit 0; }
touch $MARK; sync
VCN_BOOT=1 bash $D/vcn_up.sh --run > $D/boot.log 2>&1; rc=$?
tail -1 $D/boot.log
if [ $rc = 0 ] && grep -q '^M1 PASS' $D/boot.log; then
  sysctl debug.phxvcn=1 debug.phxmmvm=1 | tr '\n' ' '; echo
  sysctl -n debug.phxvcn_stat | cut -c1-60
else
  echo "bring-up failed (rc $rc): see $D/boot.log"
fi
rm -f $MARK; sync
echo "done $(date '+%T')"

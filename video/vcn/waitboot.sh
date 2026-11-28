#!/bin/bash
# waitboot.sh: returns once phxboot has logged "done" in the section of the current boot
bt=$(sysctl -n kern.boottime | sed -E 's/.* sec = ([0-9]+),.*/\1/')
while :; do
  n=$(grep -n '^== ' /var/log/phxboot.log | tail -1 | cut -d: -f1)
  h=$(sed -n "${n}p" /var/log/phxboot.log | awk '{print $2" "$3}')
  hs=$(date -j -f '%Y-%m-%d %H:%M:%S' "$h" +%s 2>/dev/null || echo 0)
  if [ "$hs" -ge "$bt" ] && sed -n "${n},\$p" /var/log/phxboot.log | grep -q '^done'; then break; fi
  sleep 3
done
sed -n "${n},\$p" /var/log/phxboot.log | grep -E '^==|on the panel|^done' | tr '\n' ' '; echo

#!/bin/bash
# SPDX-License-Identifier: MIT
# install.sh (root): install what build.sh built, plus VCN's boot-time bring-up.
#
#   out/decoder/*.dylib          -> PhxGPU/NVMTLDriver.bundle/Contents/MacOS (next to the Metal plugin, which registers
#                                   the decoder in every Metal process but WindowServer; the bundle is sealed again)
#   out/libvulkan_radeon_vcn.dylib -> PhxGPU/nvmtl (the decoder's own RADV; the plugin keeps libvulkan_radeon.dylib)
#   vcn/                          -> /Users/Shared/gpu/vcnup (vcn_up.sh + the data vcn_phx_gen.py writes)
#   vcn_4_0_2.bin                 -> /Users/Shared/gpu/fw (linux-firmware f30df53, md5 checked; not in this repository)
#   vcn/local.vcnboot.plist       -> /Library/LaunchDaemons (VCN up at every boot, after phxboot claimed the GPU)
#
# Needs: nullarc installed (phxboot, /Users/Shared/gpu/phxctl/phxctl), boot-arg phxdebug=1, PhxBringup from this branch
# (build 47 or later: VCN queue, MMHUB VM, fence fix) and the Metal plugin with NVMTLPhxdec.m (branch wujie-vcn).
# After a hibernation wake tools/phxwake/phxwake.sh runs vcnup/vcnwake.sh. Files are replaced by rename, so running
# processes keep the copy they mapped; apps started before VCN came up decode in software until they restart.
# Off: touch /Users/Shared/gpu/vcnup/off (no bring-up at boot) or PhxGPU/nvmtl/phxdec-off (decoder not registered).
set -eu
[ "$(id -u)" = 0 ] || { echo "run as root: sudo bash $0"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd); O=${OUT:-$HERE/out}
G=/System/Library/CoreServices/CoreTypes.bundle/Contents/Library/PhxGPU; M=$G/NVMTLDriver.bundle/Contents/MacOS
S=/Users/Shared/gpu
FW_URL=https://gitlab.com/kernel-firmware/linux-firmware/-/raw/f30df53f0f0601642698999c0fc03bb0f47d4d51/amdgpu/vcn_4_0_2.bin
FW_MD5=80a57662b73e69fd15adaa501072bf51

[ -d "$M" ] || { echo "no Metal plugin at $M (install nullarc first)"; exit 1; }
[ -x $S/phxctl/phxctl ] || { echo "no $S/phxctl/phxctl (install nullarc first)"; exit 1; }
for f in libphxdec_hevc.dylib libavcodec_phx.61.dylib libavutil_phx.59.dylib phxdec_inject.dylib; do
  [ -f "$O/decoder/$f" ] || { echo "missing $O/decoder/$f: run build.sh first"; exit 1; }
done
nvram boot-args 2>/dev/null | grep -q phxdebug=1 || echo "warning: boot-arg phxdebug=1 is missing; vcn_up.sh needs it"
b=$(ioreg -l | awk -F'= ' '/"phx-build"/{v=$2} END{print v}')
[ "${b:-0}" -ge 47 ] 2>/dev/null || echo "warning: PhxBringup build is '${b:-?}'; VCN needs 38+, and builds before 47 return wrong pictures under load"
[ "$(strings "$M/NVMTLDriver" 2>/dev/null | grep -c 'phxdec: ')" != 0 ] || echo "warning: this Metal plugin does not register the decoder (needs NVMTLPhxdec.m, branch wujie-vcn)"

echo "== decoder"
put(){ cp "$1" "$2/.new.$$"; chown root:wheel "$2/.new.$$"; chmod 755 "$2/.new.$$"; mv "$2/.new.$$" "$2/$(basename "$1")"; }
for f in libphxdec_hevc.dylib libavcodec_phx.61.dylib libavutil_phx.59.dylib phxdec_inject.dylib; do put "$O/decoder/$f" "$M"; done
put "$O/libvulkan_radeon_vcn.dylib" "$G/nvmtl"
# a changed file inside the bundle breaks its seal, and new processes then silently skip the plugin's libraries
codesign --force --sign - "$G/NVMTLDriver.bundle" >/dev/null 2>&1
codesign --verify --strict "$G/NVMTLDriver.bundle" && echo "bundle signature ok"

echo "== firmware"
mkdir -p $S/fw
if [ "$(md5 -q $S/fw/vcn_4_0_2.bin 2>/dev/null)" != $FW_MD5 ]; then
  curl -fsL --retry 3 -o $S/fw/vcn_4_0_2.bin.new "$FW_URL"
  [ "$(md5 -q $S/fw/vcn_4_0_2.bin.new)" = $FW_MD5 ] || { echo "vcn_4_0_2.bin md5 mismatch"; rm -f $S/fw/vcn_4_0_2.bin.new; exit 1; }
  mv $S/fw/vcn_4_0_2.bin.new $S/fw/vcn_4_0_2.bin
fi
echo "vcn_4_0_2.bin ok"

echo "== bring-up scripts"
mkdir -p $S/vcnup/diag
cp "$HERE"/vcn/*.sh "$HERE"/vcn/vcn_phx_gen.py $S/vcnup/
cp "$HERE"/vcn/diag/*.sh $S/vcnup/diag/
/usr/bin/python3 $S/vcnup/vcn_phx_gen.py >/dev/null
bash $S/vcnup/vcn_up.sh --dry >/dev/null 2>&1 && echo "vcn_up.sh data ok"
cp "$HERE"/vcn/local.vcnboot.plist /Library/LaunchDaemons/local.vcnboot.plist
chown root:wheel /Library/LaunchDaemons/local.vcnboot.plist; chmod 644 /Library/LaunchDaemons/local.vcnboot.plist
grep -q vcnwake.sh /usr/local/libexec/phxwake.sh 2>/dev/null ||
  echo "note: /usr/local/libexec/phxwake.sh does not call vcnwake.sh; install tools/phxwake from this branch for wake support"

echo
if [ "$(sysctl -n debug.phxvcn 2>/dev/null)" = 1 ]; then
  echo "VCN is up already; restart apps to load the new decoder"
else
  echo "installed. VCN comes up at the next boot (log /var/log/vcnboot.log); now, without a reboot:"
  echo "  sudo bash $S/vcnup/vcnon.sh"
fi

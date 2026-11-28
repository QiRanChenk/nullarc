#!/bin/bash
# SPDX-License-Identifier: MIT
# vtcheck.sh <clip> <frames> <reference> [rounds]: decode the first <frames> frames of <clip> through VideoToolbox with
# the VCN decoder registered in-process (out/vtdec_test + out/libphxdec_hevc.dylib), <rounds> times (default 1), and
# compare every frame's md5 with <reference>. Prints wrong frames (as ranges) and gaps over 0.3 s per round.
#
# <reference> is either FFmpeg's framemd5 of a software decode of the whole clip (decode the whole clip here too:
# <frames> counts samples in decode order, so a cut can end on a different set of frames),
#   ffmpeg -i <clip> -pix_fmt nv12 -f framemd5 ref.framemd5
# (the md5 covers the same bytes vtdec_test hashes: Y rows, then interleaved CbCr rows, visible width only),
# or lines "<frame> <md5>" in presentation order. 8-bit clips only (vtdec_test hashes x420 with two bytes per sample).
# A long clip matters: the fence race fixed in PhxBringup build 47 never showed on clips of a few hundred frames.
set -eu
[ $# -ge 3 ] || { echo "usage: vtcheck.sh <clip> <frames> <reference> [rounds]"; exit 2; }
HERE=$(cd "$(dirname "$0")" && pwd); O=${OUT:-$HERE/out}; B=$O/decoder
# the RADV build next to the decoder in out/, unless PHXDEC_ICD names another (install.sh puts it into PhxGPU/nvmtl)
export PHXDEC_ICD=${PHXDEC_ICD:-$O/libvulkan_radeon_vcn.dylib}
CLIP=$1; N=$2; REF=$3; ROUNDS=${4:-1}
for r in $(seq 1 "$ROUNDS"); do
"$B/vtdec_test" "$CLIP" "$N" "$B/libphxdec_hevc.dylib" 2>/dev/null | perl -MTime::HiRes=time -MPOSIX -e '
  open(R, $ARGV[0]) or die "reference: $!"; my $i = 0;
  while (<R>) { next if /^#/;
    if (/^\s*\d+,\s*-?\d+,\s*-?\d+,\s*\d+,\s*\d+,\s*([0-9a-f]{32})/) { $ref[$i++] = $1 }   # framemd5
    elsif (/^(\d+)\s+([0-9a-f]{32})/) { $ref[$1] = $2 } }
  # VideoToolbox hands frames over in decode order; the reference is in presentation order: compare by PTS rank
  $l = $t0 = time; $| = 1;
  while (<STDIN>) { $t = time; next unless /^frame (\d+) pts (-?\d+).*md5 (\S+)/; $n++;
    if ($t - $l > 0.3 && $1 > 0) { $gaps++; push @g, sprintf("%d(%.1fs)", $1, $t - $l) } $l = $t;
    push @fr, [$2, $3] }
  @fr = sort { $a->[0] <=> $b->[0] } @fr;
  for $f (0 .. $#fr) {
    if (!defined $ref[$f] || $fr[$f][1] ne $ref[$f]) { $bad++; $s //= $f; $e = $f }
    elsif (defined $s && $f - $e > 5) { push @o, "$s-$e"; undef $s } }
  push @o, "$s-$e" if defined $s;
  printf("%s round %d: %d frames (reference %d) in %.0f s; wrong frames %d in %d runs%s; gaps %d%s\n",
         strftime("%T", localtime(time)), $ARGV[1], $n, scalar(@ref), time - $t0, $bad, scalar(@o), @o ? " (@o)" : "",
         $gaps, @g ? " (@g)" : "");
  exit($bad || !$n ? 1 : 0);' "$REF" "$r" || rc=1
done
exit ${rc:-0}

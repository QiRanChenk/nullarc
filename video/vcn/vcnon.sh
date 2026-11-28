#!/bin/bash
# vcnon.sh (root): after phxboot's done: VCN up, kernel adopts the ring, MMHUB VM on, GC fault default page
set -u
D=/Users/Shared/gpu/vcnup
bash $D/waitboot.sh
bash $D/vcn_up.sh --run 2>&1 | tail -1
sysctl debug.phxvcn=1 debug.phxmmvm=1 | tr '\n' ' '; echo
[ "${1:-}" = nofd ] || bash $D/gcfd.sh | tail -1

#!/bin/bash
# fclr.sh (root): clear the latched GC protection fault status (FAULT_CNTL bit 0, as Linux does), print it before/after
P=/Users/Shared/gpu/phxctl/phxctl
echo "before: $(sysctl -n debug.phx_gcfault_stat | sed -E 's/.*STATUS/STATUS/; s/; tlb.*//')"
c=$($P regs 0x2824 | awk '{print $NF}')
$P wreg 0x2824 $(printf '0x%x' $(( c | 1 ))) >/dev/null; $P wreg 0x2824 $(printf '0x%x' $(( c & ~1 ))) >/dev/null
echo "after:  $(sysctl -n debug.phx_gcfault_stat | sed -E 's/.*STATUS/STATUS/; s/; tlb.*//')"

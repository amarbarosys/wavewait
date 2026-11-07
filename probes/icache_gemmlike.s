// Probe: gemm's layout. Long DRAM wait (global load + vmcnt) inside line 2, a few instructions, then cross into line 4.
// Single wave, so no other wave can warm the cache. Stall at the crossing -> gemm was warmed by other waves;
// no stall -> the prefetch rule is wrong (prefetch started before the wait).
// Launch: run_hsaco icache_gemmlike.hsaco probe_icache_gemmlike 192 32 128
#include "probe.inc"
PROBE_BEGIN probe_icache_gemmlike
  s_load_b64 s[0:1], s[0:1], null
  s_waitcnt_lgkmcnt null, 0
  v_lshlrev_b32_e32 v1, 2, v0
  fill_to probe_icache_gemmlike, 0x88, v_add_nc_u32_e32 v10, 1, v10  ; into line 2, like gemm's waits at 0x88/0x98
  global_load_b32 v5, v1, s[0:1]
  s_waitcnt_vmcnt null, 0
  fill_to probe_icache_gemmlike, 0x100, v_add_nc_u32_e32 v10, 1, v10
  v_add_nc_u32_e32 v10, 1, v10
  global_store_b32 v1, v10, s[0:1]
  s_endpgm
PROBE_END probe_icache_gemmlike, 16, 0

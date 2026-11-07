// Probe: icache in a loop. A 3-instruction loop body spread so each pass crosses into a new 256 B block and back.
// 1 wave. Run: run_hsaco gap_loop.hsaco gap_loop 192 32 128
#include "probe.inc"
PROBE_BEGIN gap_loop
	s_load_b64 s[0:1], s[0:1], null
	s_waitcnt_lgkmcnt null, 0x0
	v_lshlrev_b32_e32 v1, 2, v0
	s_mov_b32 s3, 0
.Ltop:
	s_add_u32 s3, s3, 1
	.rept 120                             // 480 B of body: the loop spans two blocks
	v_add_nc_u32_e32 v10, 1, v10
	.endr
	s_cmp_lt_u32 s3, 4
	s_cbranch_scc1 .Ltop
	global_store_b32 v1, v10, s[0:1]
	s_endpgm
PROBE_END gap_loop, 11, 0

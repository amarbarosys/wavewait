// Probe: EXEC=0. v_cmpx false on every lane, then VALU, LDS store, LDS load, global store and a wait; then EXEC restored.
// 1 wave (32 lanes), 512 B LDS. Run: run_hsaco gap_exec0.hsaco gap_exec0 192 32 128
#include "probe.inc"
PROBE_BEGIN gap_exec0
	s_load_b64 s[0:1], s[0:1], null
	s_waitcnt_lgkmcnt null, 0x0
	v_lshlrev_b32_e32 v1, 2, v0
	s_mov_b32 s4, exec_lo
	v_cmpx_gt_u32_e32 0, v0               // 0 > lane never true: EXEC = 0
	v_add_nc_u32_e32 v2, 1, v0
	ds_store_b32 v1, v2
	ds_load_b32 v3, v1
	s_waitcnt_lgkmcnt null, 0x0
	global_store_b32 v1, v2, s[0:1]
	s_mov_b32 exec_lo, s4
	v_add_nc_u32_e32 v2, 1, v0
	global_store_b32 v1, v2, s[0:1]
	s_endpgm
PROBE_END gap_exec0, 4, 512

// Probe: WMMA. 4 independent v_wmma back to back, then a dependent chain of 3 (D -> C), then a VALU reading the result.
// 1 wave. Run: run_hsaco gap_wmma.hsaco gap_wmma 192 32 128
#include "probe.inc"
PROBE_BEGIN gap_wmma
	s_load_b64 s[0:1], s[0:1], null
	s_waitcnt_lgkmcnt null, 0x0
	v_lshlrev_b32_e32 v1, 2, v0
	.irp r, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23
	v_mov_b32_e32 v\r, 0
	.endr
	v_wmma_f32_16x16x16_f16 v[32:39], v[8:15], v[16:23], v[32:39]   // independent
	v_wmma_f32_16x16x16_f16 v[40:47], v[8:15], v[16:23], v[40:47]
	v_wmma_f32_16x16x16_f16 v[48:55], v[8:15], v[16:23], v[48:55]
	v_wmma_f32_16x16x16_f16 v[56:63], v[8:15], v[16:23], v[56:63]
	v_nop
	v_nop
	.rept 3                                                           // D feeds C
	v_wmma_f32_16x16x16_f16 v[64:71], v[8:15], v[16:23], v[64:71]
	.endr
	v_add_f32_e32 v2, v64, v1
	global_store_b32 v1, v2, s[0:1]
	s_endpgm
PROBE_END gap_wmma, 72, 0

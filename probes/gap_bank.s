// Probe: LDS bank conflicts. b32 loads with lane stride 1, 2, 4, 8, 16, 32 dwords (conflict degree 1..32), one wait each.
// 1 wave, 4 KiB LDS. Run: run_hsaco gap_bank.hsaco gap_bank 192 32 128
#include "probe.inc"
PROBE_BEGIN gap_bank
	s_load_b64 s[0:1], s[0:1], null
	s_waitcnt_lgkmcnt null, 0x0
	v_lshlrev_b32_e32 v1, 2, v0
	// byte stride 4 << k, one wait each
	v_lshlrev_b32_e32 v4, 2, v0
	ds_load_b32 v10, v4
	s_waitcnt_lgkmcnt null, 0x0
	v_lshlrev_b32_e32 v4, 3, v0
	ds_load_b32 v11, v4
	s_waitcnt_lgkmcnt null, 0x0
	v_lshlrev_b32_e32 v4, 4, v0
	ds_load_b32 v12, v4
	s_waitcnt_lgkmcnt null, 0x0
	v_lshlrev_b32_e32 v4, 5, v0
	ds_load_b32 v13, v4
	s_waitcnt_lgkmcnt null, 0x0
	v_lshlrev_b32_e32 v4, 6, v0
	ds_load_b32 v14, v4
	s_waitcnt_lgkmcnt null, 0x0
	v_lshlrev_b32_e32 v4, 7, v0
	ds_load_b32 v15, v4
	s_waitcnt_lgkmcnt null, 0x0
	.irp sh, 2, 4, 7                      // stores with stride 1, 4, 32 dwords
	v_lshlrev_b32_e32 v4, \sh, v0
	ds_store_b32 v4, v1
	s_waitcnt_lgkmcnt null, 0x0
	.endr
	v_add_nc_u32_e32 v2, v10, v15
	global_store_b32 v1, v2, s[0:1]
	s_endpgm
PROBE_END gap_bank, 16, 4096

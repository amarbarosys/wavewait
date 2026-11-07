// Probe C: VGPR bank penalty (R2c) and per-op VALU latency. One wave (local 32), no cross-wave pipe effects.
// Bank = vgpr index mod 4. Groups G1..G14.
// Run: run_hsaco bank.hsaco bank 192 32 128
#include "probe.inc"
PROBE_BEGIN bank
	s_load_b64 s[0:1], s[0:1], null
	s_waitcnt_lgkmcnt null, 0x0
	v_lshlrev_b32_e32 v1, 2, v0
	// constants: v2 b2, v3 b3, v4 b0, v5 b1, v6 b2, v7 b3, v8 b0, v9 b1
	v_mov_b32_e32 v2, 1.0
	v_mov_b32_e32 v3, 2.0
	v_mov_b32_e32 v4, 0.5
	v_mov_b32_e32 v5, 4.0
	v_mov_b32_e32 v6, 1.0
	v_mov_b32_e32 v7, 2.0
	v_mov_b32_e32 v8, 0.5
	v_mov_b32_e32 v9, 4.0
	// G1 control: non-forwarded source in a different bank than the producer's dest
	v_add_f32_e32 v10, v2, v3
	v_add_f32_e32 v11, v10, v5            // v10 b2, v5 b1 | v11 b3, v6 b2
	v_add_f32_e32 v12, v11, v6
	// G2 penalty: non-forwarded source (src1) in the producer's dest bank
	v_add_f32_e32 v13, v2, v3
	v_add_f32_e32 v14, v13, v5            // v13 b1, v5 b1 | v14 b2, v4 b0
	v_add_f32_e32 v15, v14, v4
	// G3 source shares bank with the consumer's OWN dest, not with the producer's
	v_add_f32_e32 v16, v2, v3
	v_add_f32_e32 v17, v16, v5            // v16 b0, v5 b1 = b(v17) | v17 b1, v6 b2
	v_add_f32_e32 v18, v17, v6
	// G4 forwarded twice, then a penalised third op (penalty on c, visible on d)
	v_add_f32_e32 v19, v2, v3
	v_add_f32_e32 v20, v19, v19
	v_add_f32_e32 v21, v20, v8            // v20 b0, v8 b0 | v21 b1, v5 b1 -> d also penalised
	v_add_f32_e32 v22, v21, v5
	// G5 same-bank source in src0 position
	v_add_f32_e32 v23, v2, v3
	v_add_f32_e32 v24, v7, v23            // v23 b3, v7 b3 | v24 b0, v4 b0 -> c also penalised
	v_add_f32_e32 v25, v24, v4
	// G6 shift producer (LAT 9): consumer same-bank; strict R2c says no penalty (not both-limited)
	v_lshlrev_b32_e32 v26, v2, v3
	v_add_f32_e32 v27, v26, v6            // v26 b2, v6 b2 | v27 b3, v4 b0
	v_add_f32_e32 v28, v27, v4
	// G7 fma consumer with two non-forwarded same-bank sources
	v_add_f32_e32 v29, v2, v3
	v_fma_f32 v30, v29, v5, v9            // v29 b1, v5 b1, v9 b1 | v30 b2, v4 b0
	v_add_f32_e32 v31, v30, v4
	// G8 v_mov with no VGPR read (LAT 6?) feeding a dependent add
	v_mov_b32_e32 v32, 3.0
	v_add_f32_e32 v33, v32, v5            // v32 b0, v5 b1 | v33 b1, v4 b0
	v_add_f32_e32 v34, v33, v4
	// G9 v_mov from a VGPR (LAT 8?) feeding a dependent add
	v_mov_b32_e32 v35, v2
	v_add_f32_e32 v36, v35, v5            // v35 b3, v5 b1 | v36 b0, v4 b0 -> c penalised
	v_add_f32_e32 v37, v36, v4
	// G10 VOPD reading two same-bank registers, no dependency
	v_dual_add_f32 v38, v2, v6 :: v_dual_add_f32 v39, v3, v7
	// G11 VOPD consumer: X half has forwarded v40 plus same-bank v4
	v_add_f32_e32 v40, v2, v3
	v_dual_add_f32 v41, v40, v4 :: v_dual_add_f32 v42, v5, v9     // v40 b0, v4 b0 | v41 b1, v6 b2
	v_add_f32_e32 v43, v41, v6
	// G12 int dependent chain (issue spacing 5 or 1?)
	v_add_nc_u32_e32 v44, v0, v1
	v_add_nc_u32_e32 v45, v44, v1
	v_add_nc_u32_e32 v46, v45, v1
	// G13 v_cmpx then a VALU op (exec 7 or 8?)
	v_cmpx_gt_u32_e32 64, v0
	v_add_f32_e32 v47, v2, v3
	v_add_f32_e32 v48, v47, v5
	// G14 int producer, fp consumer and fp producer, int consumer
	v_add_nc_u32_e32 v49, v0, v1
	v_add_f32_e32 v50, v49, v5
	v_add_nc_u32_e32 v51, v50, v1
	// fold every group into one result so nothing is dead
	v_add_f32_e32 v52, v12, v15
	.irp r, 18, 22, 25, 28, 31, 34, 37, 39, 43, 46, 48, 51
	v_add_f32_e32 v52, v52, v\r
	.endr
	global_store_b32 v1, v52, s[0:1]
	s_endpgm
PROBE_END bank, 53, 0

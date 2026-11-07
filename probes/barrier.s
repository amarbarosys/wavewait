// Probe B: barrier release. 4 waves (2 per SIMD). Each wave spins a scalar loop whose count depends on its wave id,
// so waves reach each s_barrier at different, measured times. Six barriers, each isolating one question.
// 128 lanes, 4 KiB LDS. Run: run_hsaco barrier.hsaco barrier 192 128 512
#include "probe.inc"
.macro SPIN name, count             // loop max(1, count) times: s_add, s_cmp, s_cbranch (3 SALU per iteration)
	s_mov_b32 s3, 0
\name:
	s_add_u32 s3, s3, 1
	s_cmp_lt_u32 s3, \count
	s_cbranch_scc1 \name
.endm
PROBE_BEGIN barrier
	s_load_b64 s[0:1], s[0:1], null
	s_waitcnt_lgkmcnt null, 0x0
	v_lshrrev_b32_e32 v1, 5, v0             // v1 = wave id 0..3
	v_readfirstlane_b32 s2, v1              // s2 = wave id
	v_lshlrev_b32_e32 v14, 2, v0            // byte address per lane
	v_mov_b32_e32 v2, 1.0
	v_mov_b32_e32 v3, 2.0
	s_lshl_b32 s4, s2, 4                    // s4 = 16*wid
	s_sub_i32 s5, 48, s4                    // s5 = 16*(3-wid)
	// B1: staggered arrival, wave 3 last (SALU loop then s_barrier)
	SPIN .Ll1, s4
	s_barrier
	// B2: staggered arrival, wave 0 last
	SPIN .Ll2, s5
	s_barrier
	// B3: no work in between: all waves arrive together
	s_barrier
	// B4: wave 3 last, its last pre-barrier instruction is a ds_store with no waitcnt (memory outstanding at arrival)
	SPIN .Ll4, s4
	ds_store_b32 v14, v2
	s_barrier
	s_waitcnt_lgkmcnt null, 0x0
	// B5: wave 3 last, arrival preceded by a 3-deep dependent FP VALU chain (arrival = issue or completion?)
	SPIN .Ll5, s4
	v_add_f32_e32 v4, v2, v3
	v_add_f32_e32 v5, v4, v3
	v_add_f32_e32 v6, v5, v3
	s_barrier
	// B6: two barriers back to back
	s_barrier
	v_add_f32_e32 v7, v6, v2
	global_store_b32 v14, v7, s[0:1]
	s_endpgm
PROBE_END barrier, 15, 4096

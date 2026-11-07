// Probe: SALU and branch consuming a VALU-written SGPR with no s_delay_alu.
// v_cmp writes VCC, s_cbranch_vccnz reads it; v_readfirstlane writes s2, s_add reads it.
// Rule A: no issue stall (delta 1 after the producer). Rule B: wait for the VALU writeback.
// Launch: run_hsaco hunt_salu_valu.hsaco probe_salu_valu 192 32 128
#include "probe.inc"
PROBE_BEGIN probe_salu_valu
  s_load_b64 s[0:1], s[0:1], null
  s_waitcnt_lgkmcnt null, 0
  v_lshlrev_b32_e32 v1, 2, v0
  v_readfirstlane_b32 s2, v1  ; VALU -> SGPR -> SALU
  s_add_u32 s3, s2, 1
  .rept 4
    s_nop 0
  .endr
  v_readfirstlane_b32 s4, v1  ; one cycle apart
  s_nop 0
  s_add_u32 s5, s4, 1
  .rept 4
    s_nop 0
  .endr
  v_cmp_gt_u32_e32 16, v0  ; VALU -> VCC -> branch
  s_cbranch_vccz .Lnext
.Lnext:
  .rept 4
    s_nop 0
  .endr
  v_mov_b32_e32 v2, s3
  global_store_b32 v1, v2, s[0:1]
  s_endpgm
PROBE_END probe_salu_valu, 8, 0

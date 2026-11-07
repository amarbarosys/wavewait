// Probe D: LDS request queue depth and same-port cross-wave issue. 4 waves; waves on simd 2 (odd wave id) exit at once,
// so only simd 0 (slots 0 and 1) issues. Part 1: 12 back-to-back loads, then 12 back-to-back stores (issue stall = queue depth).
// Part 2: both simd-0 waves issue one store within a cycle of each other (the sync s0w1 anomaly, wait 8 instead of 3).
// Launch: run_hsaco lds_depth.hsaco probe_lds_depth 192 128 512
#include "probe.inc"
PROBE_BEGIN probe_lds_depth
  s_load_b64 s[0:1], s[0:1], null
  s_waitcnt_lgkmcnt null, 0
  v_lshrrev_b32_e32 v1, 5, v0  ; wave id
  v_and_b32_e32 v2, 1, v1  ; odd wave id -> simd 2
  v_lshlrev_b32_e32 v3, 2, v0  ; byte address
  v_mov_b32_e32 v4, 7
  v_cmpx_eq_u32_e32 0, v2  ; keep only even waves (simd 0)
  s_cbranch_execz .Lend
  ; part 1a: 12 loads back to back
  ds_load_b32 v8, v3 offset:0
  ds_load_b32 v9, v3 offset:16
  ds_load_b32 v10, v3 offset:32
  ds_load_b32 v11, v3 offset:48
  ds_load_b32 v12, v3 offset:64
  ds_load_b32 v13, v3 offset:80
  ds_load_b32 v14, v3 offset:96
  ds_load_b32 v15, v3 offset:112
  ds_load_b32 v16, v3 offset:128
  ds_load_b32 v17, v3 offset:144
  ds_load_b32 v18, v3 offset:160
  ds_load_b32 v19, v3 offset:176
  s_waitcnt_lgkmcnt null, 0
  ; part 1b: 12 stores back to back
  ds_store_b32 v3, v4 offset:0
  ds_store_b32 v3, v4 offset:16
  ds_store_b32 v3, v4 offset:32
  ds_store_b32 v3, v4 offset:48
  ds_store_b32 v3, v4 offset:64
  ds_store_b32 v3, v4 offset:80
  ds_store_b32 v3, v4 offset:96
  ds_store_b32 v3, v4 offset:112
  ds_store_b32 v3, v4 offset:128
  ds_store_b32 v3, v4 offset:144
  ds_store_b32 v3, v4 offset:160
  ds_store_b32 v3, v4 offset:176
  s_waitcnt_lgkmcnt null, 0
  v_add_f32_e32 v5, v8, v9  ; VALU so both waves re-align on the mem-after-VALU rule
  ds_store_b32 v3, v5  ; part 2: one store per wave, waves 0 and 2 issue ~1 cycle apart
  s_waitcnt_lgkmcnt null, 0
  global_store_b32 v3, v5, s[0:1]
.Lend:
  s_endpgm
PROBE_END probe_lds_depth, 24, 4096

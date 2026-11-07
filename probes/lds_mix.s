// Probe A: LDS service order. 4 waves (2 per SIMD) issue back-to-back stores and loads of mixed width,
// so requests from both SIMDs and both slots tie at the LDS unit.
// Launch: run_hsaco lds_mix.hsaco probe_lds_mix 192 128 512
#include "probe.inc"
PROBE_BEGIN probe_lds_mix
  s_load_b64 s[0:1], s[0:1], null
  s_waitcnt_lgkmcnt null, 0
  v_lshlrev_b32_e32 v1, 2, v0  ; 4 B per lane: conflict-free b32 accesses
  v_add_nc_u32_e32 v15, 512, v1
  v_add_nc_u32_e32 v16, 1024, v1
  v_mov_b32_e32 v2, 1
  v_mov_b32_e32 v3, 2
  ; burst 1: store, load, store, load
  ds_store_b32 v1, v2
  ds_load_b32 v6, v1
  ds_store_b32 v15, v3
  ds_load_b32 v7, v15
  s_waitcnt_lgkmcnt null, 0
  ; burst 2: three stores then three loads
  ds_store_b32 v1, v2
  ds_store_b32 v15, v3
  ds_store_b32 v16, v2
  ds_load_b32 v6, v1
  ds_load_b32 v7, v15
  ds_load_b32 v8, v16
  s_waitcnt_lgkmcnt null, 0
  ; burst 3: loads first, then stores
  ds_load_b32 v6, v1
  ds_load_b32 v7, v15
  ds_store_b32 v16, v2
  ds_store_b32 v1, v3
  s_waitcnt_lgkmcnt null, 0
  v_add_nc_u32_e32 v6, v6, v7
  global_store_b32 v1, v6, s[0:1]
  s_endpgm
PROBE_END probe_lds_mix, 24, 2048

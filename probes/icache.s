// Probe I: instruction-cache fetch. Two 256 B-window crossings in one kernel.
// Region 1: short VALU run after the s_load wait, then cross 0x200 with no further DRAM wait.
//   Hypothesis H0 (256 B window, fetch on demand, no prefetch): 475-cycle stall at the first
//   instruction in 0x200.. (as in probe_bank, pc 0x200).
// Region 2: an s_load wait immediately before crossing 0x300, giving the front end ~600 cycles
//   to fetch the next window while the wave is stalled on DRAM.
//   H0 predicts the stall disappears (0) if the fetch of 0x300.. completed during the wait;
//   if it does not, H0 predicts another ~475 stall.
// fill_to boundaries (0x100, 0x200) are code-relative: kernel entry is 256 B aligned.
// PF=1..3 (as -defsym PF=n) arms the ISA prefetch distance (64 B lines ahead of PC) first.
// Build: probes/build.sh, PF: PF=2 probes/build.sh. Launch: run_hsaco icache.hsaco probe_icache 192 32 128
#include "probe.inc"
.ifndef PF
.set PF, 0
.endif
PROBE_BEGIN probe_icache
.if PF
  s_set_inst_prefetch_distance PF
.endif
  s_load_b64 s[0:1], s[0:1], null
  s_waitcnt_lgkmcnt null, 0
  v_lshlrev_b32_e32 v1, 2, v0
  fill_to probe_icache, 0x100, v_add_f32_e32 v52, v52, v2
  v_add_f32_e32 v52, v52, v2  ; region 1: first instruction of the next 256 B
  s_load_b64 s[4:5], s[0:1], null  ; region 2: DRAM wait, then cross the next window
  s_waitcnt_lgkmcnt null, 0
  fill_to probe_icache, 0x200, v_add_f32_e32 v52, v52, v2
  v_add_f32_e32 v52, v52, v2
  global_store_b32 v1, v52, s[0:1]
  s_endpgm
PROBE_END probe_icache, 56, 0

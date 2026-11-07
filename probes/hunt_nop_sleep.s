// Probe: s_nop and s_sleep issue gaps, then one VALU and an s_nop before the end.
// Launch: run_hsaco hunt_nop_sleep.hsaco hunt_nop_sleep 192 32 128
#include "probe.inc"
PROBE_BEGIN hunt_nop_sleep
  s_nop 0
  s_nop 5
  s_sleep 1
  v_mov_b32_e32 v0, 1
  s_nop 0
  s_endpgm
PROBE_END hunt_nop_sleep, 8, 0

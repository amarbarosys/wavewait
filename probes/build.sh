#!/usr/bin/env bash
# Assemble the hand-written gfx1100 probes (probes/NAME.s) to code objects: probes/build.sh [OUTDIR] [NAME ...]
# Default: OUTDIR build/probes, every probe. PF=1..3 probes/build.sh OUT icache arms icache's s_set_inst_prefetch_distance.
# LLVM = the dir with clang and ld.lld (default: /opt/rocm/llvm/bin, else /usr/bin). CPU only.
set -euo pipefail
cd "$(dirname "$0")"
out=${1:-../build/probes}; shift || true
if [ -z "${LLVM:-}" ]; then
  for d in /opt/rocm/llvm/bin /usr/bin; do [ -x "$d/clang" ] && [ -x "$d/ld.lld" ] && { LLVM=$d; break; }; done
fi
[ -n "${LLVM:-}" ] || { echo "FAIL build: clang and ld.lld not found in /opt/rocm/llvm/bin or /usr/bin (install clang and lld, or set LLVM)"; exit 1; }
mkdir -p "$out"
for p in ${@:-$(ls *.s | sed 's/\.s$//')}; do
  [ -f "$p.s" ] || { echo "FAIL build: no probes/$p.s"; exit 1; }
  "$LLVM/clang" -target amdgcn-amd-amdhsa -mcpu=gfx1100 -nogpulib -x assembler-with-cpp ${PF:+-Wa,-defsym,PF=$PF} -c "$p.s" -o "$out/$p.o" 2> "$out/$p.err" \
    || { cat "$out/$p.err"; echo "FAIL build: clang $p"; exit 1; }
  "$LLVM/ld.lld" -shared "$out/$p.o" -o "$out/$p.hsaco" || { echo "FAIL build: ld.lld $p"; exit 1; }
  echo "ok $out/$p.hsaco"
done

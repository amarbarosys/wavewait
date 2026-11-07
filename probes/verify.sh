#!/usr/bin/env bash
# Build every probe (probes/*.s) and compare each against probes/golden/NAME.{hex,dis,kd}: code bytes up to s_endpgm,
# disassembly, kernel-descriptor words (lds, private, rsrc1-3, properties). Golden = the instruction streams the probes
# always had, from before they were assembly. Pure CPU, no GPU. OUT = build dir (default .work/probes-build).
set -euo pipefail
cd "$(dirname "$0")"
out=${OUT:-../.work/probes-build}
probes=$(cd golden && ls *.hex | sed 's/\.hex$//')
[ "$(echo "$probes" | wc -l)" = "$(ls *.s | wc -l)" ] || { echo "FAIL verify: probes/*.s and probes/golden/*.hex are not the same set"; exit 1; }
./build.sh "$out" >/dev/null || { echo "FAIL verify: build (log $out/*.err)"; exit 1; }
objdump=${OBJDUMP:-/usr/bin/llvm-objdump}   # the system LLVM, as check.sh: ROCm 7.2's prints some gfx11 VOP3 as .long
fail=0
for p in $probes; do
  f=$out/$p.hsaco
  "$objdump" -d --mcpu=gfx1100 "$f" > "$out/$p.dump"
  "$objdump" -s -j .rodata "$f" > "$out/$p.rodata"
  # code: dwords from the disassembly comments as little-endian bytes, up to and including s_endpgm
  hex=$(awk '
    /\/\/ +[0-9A-F]+: [0-9A-F]/ { l = $0; sub(/.*\/\/ +[0-9A-F]+: /, "", l); sub(/ *<.*$/, "", l); n = split(l, w, " ")
      for (i = 1; i <= n; i++) printf "%s%s%s%s", tolower(substr(w[i],7,2)), tolower(substr(w[i],5,2)), tolower(substr(w[i],3,2)), tolower(substr(w[i],1,2))
      if ($0 ~ /s_endpgm/) done = 1 }
    done { exit }' "$out/$p.dump")
  [[ "$hex" == "$(cat golden/$p.hex)" ]] || { echo "FAIL $p: code bytes differ from golden/$p.hex"; fail=1; }
  dis=$(awk '/^\t[a-z]/ && !/amdgcn_target/ { sub(/ *\/\/ .*$/, ""); sub(/^\t/, ""); sub(/ *<.*$/, ""); print; if ($0 ~ /^s_endpgm/) done = 1 }
    done { exit }' "$out/$p.dump")
  [[ "$dis" == "$(cat golden/$p.dis)" ]] || { echo "FAIL $p: disassembly differs from golden/$p.dis"; diff <(echo "$dis") golden/$p.dis | head -5; fail=1; }
  kd=$(awk '
    function h2d(s,  i, d, c) { d = 0; for (i = 1; i <= length(s); i++) { c = index("0123456789abcdef", substr(s,i,1)) - 1; d = d * 16 + c } return d }
    function le(v) { return h2d(substr(v,7,2) substr(v,5,2) substr(v,3,2) substr(v,1,2)) }
    /^ [0-9a-f]+ / { off = h2d($1); if (base == "") base = off; for (i = 2; i <= 5; i++) d[off - base + 4*(i-2)] = le($i) }
    END { printf "lds=%d priv=%d rsrc1=0x%08x rsrc2=0x%08x rsrc3=0x%08x kcp=0x%04x", d[0], d[4], d[48], d[52], d[44], d[56] % 65536 }' "$out/$p.rodata")
  [[ "$kd" == "$(cat golden/$p.kd)" ]] || { echo "FAIL $p: descriptor [$kd] != [$(cat golden/$p.kd)]"; fail=1; continue; }
  echo "ok $p"
done
exit $fail

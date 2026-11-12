#!/usr/bin/env bash
# att-trim.sh RUNDIR OUT [N]: a one-dispatch rocprofv3 --att run dir cut down to its N earliest-ending waves
# (default 1), small enough to commit under fixtures/. OUT gets the same layout `wavewait app` reads:
#   - the .att cut at the first byte where those N waves have all ended (bisected on app's waves/open columns),
#   - filenames.json listing only those N waves (app walks only the waves it lists),
#   - code.json and the code objects unchanged; the .att and .out are gzipped (check.sh gunzips into a temp dir).
# When: a real capture shows a walk case no fixture covers and the full trace is too big (quantus: 94 MB).
# Gotchas: the cut trace still holds the other slots' packets up to the cut, so size grows with the SIMD's
# occupancy; AMD's per-wave se*.json files are not copied (tools/amd_oracle.py's per-wave check needs the full run).
set -euo pipefail
run=${1:?usage: att-trim.sh RUNDIR OUT [N]} out=${2:?OUT} n=${3:-1}
here=$(cd "$(dirname "$0")/.." && pwd)
ww="$here/build/wavewait"
[ -x "$ww" ] || { echo "FAIL trim: build/wavewait missing (run check.sh)"; exit 1; }
mapfile -t atts < <(ls "$run"/*/*_shader_engine_*.att 2>/dev/null)
[ "${#atts[@]}" = 1 ] || { echo "FAIL trim: ${#atts[@]} .att files under $run, want exactly 1 dispatch"; exit 1; }
att=${atts[0]}
host=$(basename "$(dirname "$att")")
ddir=$(ls -d "$run"/ui_output_agent_*_dispatch_* | head -1)
[ -f "$ddir/filenames.json" ] || { echo "FAIL trim: no filenames.json in $ddir"; exit 1; }
rm -rf "$out"; mkdir -p "$out/$host" "$out/$(basename "$ddir")"
cp "$ddir/code.json" "$out/$(basename "$ddir")/"
cp "$run/$host"/*_code_object_id_*.out "$out/$host/"
python3 -I -c '
import json, sys
t = json.load(open(sys.argv[1])); n = int(sys.argv[3])
ws = sorted((v[2], se, sm, sl, k) for se, a in t["wave_filenames"].items() for sm, b in a.items() for sl, c in b.items() for k, v in c.items())[:n]
if len(ws) != n: sys.exit("FAIL trim: the run has only %d waves" % len(ws))
keep = {}
for _, se, sm, sl, k in ws:
    keep.setdefault(se, {}).setdefault(sm, {}).setdefault(sl, {})[k] = t["wave_filenames"][se][sm][sl][k]
t["wave_filenames"] = keep
json.dump(t, open(sys.argv[2], "w"), separators=(",", ":"))
' "$ddir/filenames.json" "$out/$(basename "$ddir")/filenames.json" "$n"
cut="$out/$host/$(basename "$att")"
ok() {  # the N waves all started and ended inside the first $1 bytes
  head -c "$1" "$att" > "$cut"
  [ "$("$ww" app "$out" --allow-mism | awk 'NR==2{print $3, $(NF-2)}')" = "$n 0" ]
}
size=$(stat -c %s "$att") lo=0 hi=65536
while [ "$hi" -lt "$size" ] && ! ok "$hi"; do lo=$hi; hi=$((hi * 2)); done
[ "$hi" -lt "$size" ] || hi=$size
while [ $((hi - lo)) -gt 256 ]; do mid=$(((lo + hi) / 2)); if ok "$mid"; then hi=$mid; else lo=$mid; fi; done
ok "$hi" || { echo "FAIL trim: the $n waves never end inside $att"; exit 1; }
"$ww" app "$out" | sed -n 2p
gzip -9n "$cut" "$out/$host"/*.out
echo "ok att-trim: $n waves, $hi of $size trace bytes -> $out ($(du -sh "$out" | cut -f1))"

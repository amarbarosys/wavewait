#!/usr/bin/env bash
# comfy-prof.sh OUT GRAPH1.api.json [GRAPH2.api.json ...]: kernel profile of ANY ComfyUI API graph, one resident server under rocprofv3
# --kernel-trace, the graphs run one after the other (graph 1 = cold/warmup, the last = the warm shot to read), as a gpu-wait job.
# Graphs must differ (ComfyUI skips a prompt it has cached). Per shot: OUT/stages-K.tsv (tools/comfy_stages.py, boot-clock ns), OUT/rank-K.txt
# (`wavewait rank OUT/kt --stages`: per node busy, idle, top kernel), OUT/wall.tsv (shot, wall s). Ends with the last shot's table.
# Env: COMFY (default ~/Projects/imports/ComfyUI-v0.43.0), COMFY_FLAGS (server flags), COMFY_EXTRA (more flags, default the ltx paths file),
# SRVENV ("K=V K=V" for the server), PORT (8190), VRAM (23), MEM (36, the measured ComfyUI peak 35 GB; 32 for --cache-none/LRU arms), PRIO (60), TIMEOUT (1500 s), SHOT_TIMEOUT (600 s), MIN_FREE_GB (15).
# rocprofv3 writes at SIGINT and the server then lingers: killed by PID once finalized (docs/pytorch.md). A GPU reset in the kernel log kills the job.
set -uo pipefail
out=${1:?usage: comfy-prof.sh OUT GRAPH.api.json [GRAPH.api.json ...]}; shift
[ "$#" -ge 1 ] || { echo "FAIL prof: no graph"; exit 1; }
root=$(cd "$(dirname "$0")/.." && pwd)
if [ -z "${COMFY_PROF_INNER:-}" ]; then
  graphs=(); for g in "$@"; do graphs+=("$(realpath "$g")"); done
  exec gpu-wait run --priority "${PRIO:-60}" --vram "${VRAM:-23}" --mem "${MEM:-36}" --timeout "${TIMEOUT:-1500}" --label comfy-prof -- env -u HSA_OVERRIDE_GFX_VERSION COMFY_PROF_INNER=1 \
    COMFY="${COMFY:-}" COMFY_FLAGS="${COMFY_FLAGS:-}" COMFY_EXTRA="${COMFY_EXTRA:-}" SRVENV="${SRVENV:-}" PORT="${PORT:-}" SHOT_TIMEOUT="${SHOT_TIMEOUT:-}" MIN_FREE_GB="${MIN_FREE_GB:-}" "$0" "$(realpath -m "$out")" "${graphs[@]}"
fi
set -m
comfy=${COMFY:-$HOME/Projects/imports/ComfyUI-v0.43.0}; port=${PORT:-8190}; floor=${MIN_FREE_GB:-15}; st=${SHOT_TIMEOUT:-600}
flags=${COMFY_FLAGS:---use-pytorch-cross-attention --reserve-vram 0.5 --disable-pinned-memory}
extra=${COMFY_EXTRA:---extra-model-paths-config .work/ltx/paths.yaml}
[ ! -e "$out" ] || { echo "FAIL prof: $out exists"; exit 1; }
mkdir -p "$out"; out=$(cd "$out" && pwd)
ss -ltn | grep -q ":$port " && { echo "FAIL prof: port $port is taken"; exit 1; }
free_gb() { df --output=avail -BG "$HOME" | tail -1 | tr -dc 0-9; }
since=$(date '+%F %T')
resets() { journalctl -k --since "$since" --no-pager 2> /dev/null | grep -c 'GPU reset begin'; }
cd "$comfy" || { echo "FAIL prof: no $comfy"; exit 1; }
# shellcheck disable=SC2086
env $SRVENV /opt/rocm/bin/rocprofv3 --kernel-trace --memory-copy-trace --output-format csv --preload librocprofiler-sdk.so -d "$out/kt" -- \
  .venv/bin/python main.py --listen 127.0.0.1 --port "$port" $flags $extra > "$out/server.log" 2>&1 &
job=$!; pid=
cleanup() { [ -z "$pid" ] || kill -KILL "$pid" 2> /dev/null; kill -KILL -- "-$job" 2> /dev/null; }
trap cleanup EXIT
for _ in $(seq 240); do curl -s "127.0.0.1:$port/system_stats" > /dev/null && break; kill -0 "$job" 2> /dev/null || { echo "FAIL prof: server died at start, log $out/server.log"; exit 1; }; sleep 1; done
pid=$(ss -ltnp | grep ":$port " | grep -oE 'pid=[0-9]+' | head -1 | cut -d= -f2)
[ -n "$pid" ] || { echo "FAIL prof: no server on $port, log $out/server.log"; exit 1; }
echo "server $pid up, $(free_gb) GB free"
( while kill -0 "$pid" 2> /dev/null; do
    if [ "$(free_gb)" -lt "$floor" ]; then echo "FAIL disk: under $floor GB free, killing $pid"; kill -KILL "$pid"; touch "$out/disk-abort"; exit 1; fi
    if [ "$(resets)" != 0 ]; then echo "FAIL reset: GPU reset in the kernel log, killing $pid"; kill -KILL "$pid"; touch "$out/reset-abort"; exit 1; fi
    sleep 5
  done ) &
k=0; rc=0
for g in "$@"; do
  k=$((k + 1))
  cp "$g" "$out/graph-$k.json"
  .venv/bin/python -I "$root/tools/comfy_stages.py" "$out/stages-$k.tsv" "$out/graph-$k.json" "127.0.0.1:$port" &
  stg=$!; sleep 1
  t0=$(date +%s)
  jq -c '{prompt: ., client_id: "comfy_stages"}' "$g" | curl -sf -X POST -H 'Content-Type: application/json' -d @- "127.0.0.1:$port/prompt" > "$out/prompt-$k.json" \
    || { echo "FAIL prof: shot $k rejected: $(head -c 400 "$out/prompt-$k.json" 2> /dev/null)"; rc=1; break; }
  for _ in $(seq "$st"); do kill -0 "$stg" 2> /dev/null || break; sleep 1; done
  kill -0 "$stg" 2> /dev/null && { echo "FAIL prof: shot $k not done in $st s"; kill "$stg"; rc=1; break; }
  grep -q execution_success "$out/stages-$k.tsv" || { echo "FAIL prof: shot $k ended without execution_success: $(tail -1 "$out/stages-$k.tsv")"; rc=1; break; }
  printf '%s\t%s\n' "$k" "$(( $(date +%s) - t0 ))" >> "$out/wall.tsv"
  echo "SHOT $k wall $(( $(date +%s) - t0 )) s"
done
kill -INT "$pid" 2> /dev/null
for _ in $(seq 300); do grep -q 'found chained signal handler' "$out/server.log" && break; kill -0 "$pid" 2> /dev/null || break; sleep 1; done
grep -q 'found chained signal handler' "$out/server.log" || echo "WARN prof: no end of rocprofv3's finalization in 300 s, killing anyway"
sleep 2; kill -KILL "$pid" 2> /dev/null; pid=; wait "$job" 2> /dev/null
[ "$(resets)" = 0 ] || { touch "$out/reset-abort"; echo "FAIL reset: GPU reset in the kernel log"; exit 1; }
[ "$rc" = 0 ] || exit "$rc"
n=$(find "$out/kt" -name '*_kernel_trace.csv' 2> /dev/null | wc -l)
[ "$n" -gt 0 ] || { echo "FAIL prof: no kernel trace after a clean stop, log $out/server.log"; exit 1; }
for i in $(seq "$k"); do "$root/build/wavewait" rank "$out/kt" --top 15 --stages "$out/stages-$i.tsv" > "$out/rank-$i.txt" 2>&1 || { echo "FAIL rank: shot $i, see $out/rank-$i.txt"; exit 1; }; done
for i in $(seq "$k"); do "$root/tools/kclass.sh" "$out/kt" "$out/stages-$i.tsv" > "$out/classes-$i.txt" 2>&1 || { echo "FAIL kclass: shot $i, see $out/classes-$i.txt"; exit 1; }; done
echo "ok comfy-prof: $k shots, $n kernel traces, $(du -sh "$out" | cut -f1), $(free_gb) GB free; last shot (classes, then rank):"
cat "$out/classes-$k.txt" "$out/rank-$k.txt"

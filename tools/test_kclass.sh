#!/usr/bin/env bash
# test_kclass.sh: CPU gate for tools/kclass.sh on fixtures/rank (60 dispatches, two node windows). Checks the two node lines and their dispatch
# counts, that class shares sum to 100 %, that --steps without progress events gives the same lines, and two negative controls (no trace dir,
# empty stages file) that must FAIL. A table that prints for any input proves nothing.
set -euo pipefail
cd "$(dirname "$0")/.."
f=fixtures/rank
out=$(tools/kclass.sh $f $f/stages.tsv)
[ "$(echo "$out" | wc -l)" = 2 ] || { echo "FAIL kclass test: expected 2 node lines, got: $out"; exit 1; }
echo "$out" | grep -q 'KSampler .* n 35 ' || { echo "FAIL kclass test: KSampler n != 35"; exit 1; }
echo "$out" | grep -q 'SaveGLB .* n 25 ' || { echo "FAIL kclass test: SaveGLB n != 25"; exit 1; }
echo "$out" | awk '{ s = 0; for (i = 1; i <= NF; i++) if ($i ~ /%$/ && $(i - 1) ~ /^(gemm|attn|conv|norm|bitops|elem|other)$/) { v = $i; sub(/%/, "", v); s += v }
  if (s < 99.5 || s > 100.5) { print "FAIL kclass test: shares sum " s " on: " $0; bad = 1 } } END { exit bad }'
[ "$(tools/kclass.sh $f $f/stages.tsv --steps)" = "$out" ] || { echo "FAIL kclass test: --steps differs without progress events"; exit 1; }
if tools/kclass.sh /nonexistent $f/stages.tsv > /dev/null 2>&1; then echo "FAIL kclass test: no trace dir did not fail"; exit 1; fi
if tools/kclass.sh $f /nonexistent.tsv > /dev/null 2>&1; then echo "FAIL kclass test: missing stages file did not fail"; exit 1; fi
echo "ok test_kclass: 2 node lines, n 35 and 25, shares sum to 100, --steps equal, negative controls fail"

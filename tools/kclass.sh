#!/usr/bin/env bash
# kclass.sh RUNDIR STAGES.tsv [--steps]: (--steps cuts a window per sampler step at the progress events: step N covers the time up to its event, so a
# node's first step includes any model load inside the node.) Per ComfyUI node window of a rocprofv3 kernel trace: wall s, GPU busy s (union of kernel intervals) and %,
# dispatches, then kernel time by class (share of the summed kernel time). Classes come from the kernel NAME: gemm (Cijk, hipBLASLt, wmma),
# attn (attn, flash, sdpa, softmax), conv (conv, Im2d, Col2Im, MIOpen), norm, bitops (Bitwise/shift functors: the GGUF dequant unpack),
# elem (other elementwise, copy, fill, reduce, cat, index), other. Dequant has no kernel of its own in torch: bitops is its proxy, and the
# float multiply that follows lands in elem. Windows are `executing` event to next event of the stages file (tools/comfy_stages.py).
set -euo pipefail
run=${1:?usage: kclass.sh RUNDIR STAGES.tsv}; st=${2:?usage: kclass.sh RUNDIR STAGES.tsv}
[ -s "$st" ] || { echo "FAIL kclass: no stages file $st"; exit 1; }
mapfile -t csvs < <(find "$run" -name '*_kernel_trace.csv')
[ "${#csvs[@]}" -gt 0 ] || { echo "FAIL kclass: no *_kernel_trace.csv under $run"; exit 1; }
tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
cat "${csvs[@]}" | awk '
  /^"Kind"/ { next }
  { if (!match($0, /",[0-9]+(,[0-9]+){13}$/)) { bad++; next }
    n = split(substr($0, RSTART + 2), f, ","); name = substr($0, 1, RSTART)
    c = "other"
    if (name ~ /Bitwise|RShift|LShift|bitwise|rshift|lshift/) c = "bitops"
    else if (name ~ /Cijk|[Gg]emm|hipblaslt|wmma|[Tt]ensile|matmul/) c = "gemm"
    else if (name ~ /attn|[Aa]ttention|flash|sdpa|fmha|aotriton|[Ss]oftmax/) c = "attn"
    else if (name ~ /[Cc]onv|Im2d|[Cc]ol2[Ii]m|[Ii]m2[Cc]ol|vol2col|[Mm][Ii][Oo]pen|winograd/) c = "conv"
    else if (name ~ /[Nn]orm/) c = "norm"
    else if (name ~ /elementwise|copy|[Ff]ill|reduce|CatArray|index|[Pp]ermute|transpose/) c = "elem"
    print f[2], f[3], c }
  END { if (bad) print "WARN kclass: " bad " rows not parsed" > "/dev/stderr" }' | sort -n -k1,1 > "$tmp"
awk -F'\t' -v steps="${3:+1}" '
  FNR == NR { if ($2 == "progress" && steps) { if (nw > 0 && we[nw] == "") we[nw] = $1; nw++; ws[nw] = $1; wn[nw] = $3; wc[nw] = $4 " step " ($5 + 1) "/" $6; next }
              if ($2 != "executing" && $2 != "execution_success" && $2 != "execution_error") next
              if (nw > 0 && we[nw] == "") we[nw] = $1
              if ($2 == "executing" && $3 != "") { nw++; ws[nw] = $1; wn[nw] = $3; wc[nw] = $4 }
              next }
  { split($0, a, " "); s = a[1]; e = a[2]; c = a[3]
    if (w == 0) w = 1
    while (w <= nw && we[w] != "" && s >= we[w]) w++
    if (w > nw || s < ws[w]) next
    cnt[w]++; d = e - s; t[w, c] += d; tot[w] += d
    if (s > cur[w]) { busy[w] += d; cur[w] = e } else if (e > cur[w]) { busy[w] += e - cur[w]; cur[w] = e } }
  END { split("gemm attn conv norm bitops elem other", order, " ")
    for (i = 1; i <= nw; i++) { if (we[i] == "") continue
      wall = (we[i] - ws[i]) / 1e9
      if (wall < 0.05 && cnt[i] < 5) continue
      line = sprintf("%-4s %-24s wall %7.2f s  busy %7.2f s %5.1f%%  n %-7d", wn[i], wc[i], wall, busy[i] / 1e9, wall > 0 ? 100 * busy[i] / 1e9 / wall : 0, cnt[i])
      for (j = 1; j <= 7; j++) { c = order[j]; if (tot[i] > 0 && t[i, c] / tot[i] >= 0.005) line = line sprintf("  %s %.1f%%", c, 100 * t[i, c] / tot[i]) }
      print line } }' "$st" "$tmp"

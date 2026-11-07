# llvm-objdump -d --mcpu=gfx1100 CODEOBJ | awk -f pcmap.awk > pcmap.tsv   (pc, size, first dword, text)
# POSIX awk (mawk too): no strtonum
function hex(s,  i, v) { v = 0; s = toupper(s); for (i = 1; i <= length(s); i++) v = v * 16 + index("0123456789ABCDEF", substr(s, i, 1)) - 1; return v }
match($0, /^[ \t]+[^ \t].*\/\/ *[0-9A-F]+:( [0-9A-F]{8})+/) {
  i = index($0, "//"); t = substr($0, 1, i-1); sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t)
  rest = substr($0, i+2); sub(/^ */, "", rest); c = index(rest, ":")
  n = split(substr(rest, c+1), w, " "); for (k = 1; k <= n && w[k] ~ /^[0-9A-F]{8}$/; k++) ; n = k - 1
  printf "%d\t%d\t%d\t%s\n", hex(substr(rest, 1, c-1)), 4*n, hex(w[1]), t }

# rules

What broke -> the rule. One line each, newest last.

- code_json() read the kernel label from the first row of rocprofv3's code.json; on a kernel that sits above a device function the label row came after the instruction rows, the walk entered the wrong function and priced 0 cycles (2026-11-12) -> never rely on the row order of AMD's decoder output; find the row by what it is.
- The mismatch count was assigned after the "no rows" early return, so 684 lost waves printed as mism 0 and the failure blamed the capture (2026-11-12) -> every counter a caller reads is set before the first early return; a walk with waves and 0 rows is a walk failure, not an empty trace.
- s_swappc_b64 was walked as a fall-through; the first Mojo kernel with a non-inlined function desynced there (2026-11-12) -> an instruction that can change the pc (s_branch, s_cbranch, s_call, s_setpc, s_swappc) is a jump in the walk AND in the packet class table; a new one gets a fixture.
- A stash round trip to prove a check fails on the old source left the old build/wavewait while .work/check.ok still matched the tree (2026-11-12) -> the receipt names the binary (check.sh); after any checkout or stash of src/, run check.sh before reading a number.
- `cmd | grep -q` under pipefail failed once in 5 runs of check.sh: grep left at its first match and the writer died of SIGPIPE (2026-11-12) -> in check.sh pipe into `grepq`, never `grep -q`; here-strings may keep `grep -q`.
- Named a Mojo variable `fn` (a removed keyword: parse error, one build lost) (2026-11-12) -> no variable named fn, def, var, ref, out, mut.
- Expected the hot rows of quantus inside permute; measured, the top rows by charged cycles are the kernel's first VALU instructions (new waves queued behind older ones), permute holds 53% spread over 25505 rows (2026-11-12) -> on a straight-line callee read `cycles by function` and `--by-class` before the top-N rows; a top-N table cannot show a cost spread over thousands of rows.

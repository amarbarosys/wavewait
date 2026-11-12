# wavewait

<!-- badges -->
[![check](https://github.com/amarbarosys/wavewait/actions/workflows/check.yml/badge.svg?branch=main)](https://github.com/amarbarosys/wavewait/actions/workflows/check.yml) [![latest release](https://img.shields.io/github/v/release/amarbarosys/wavewait)](https://github.com/amarbarosys/wavewait/releases/latest) [![license](https://img.shields.io/github/license/amarbarosys/wavewait)](https://github.com/amarbarosys/wavewait/blob/main/LICENSE) [![checks](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/amarbarosys/wavewait/badges/checks.json)](https://github.com/amarbarosys/wavewait/actions/workflows/check.yml)
<!-- /badges -->

Cycle-level stall profile of any gfx1100 kernel (hipcc, Mojo, hand asm) from a real SQTT thread trace
on the 7900 XTX, captured through rocprofv3 ATT (any HIP program or code object).
Shows, per instruction, how many cycles each wave waited before it issued.

`tools/doctor.sh` says what this machine still needs to capture, with the fix.

Docs: [`docs/api.md`](docs/api.md) (every subcommand, flag and exit code), [`docs/design.md`](docs/design.md) (layout, data flow, memory, what was rejected), [`docs/pytorch.md`](docs/pytorch.md) (whole PyTorch process).

## Use: rocprofv3 ATT

ROCm's thread trace writes raw RDNA3 SQTT for any HIP program as it is (no ELF swap, any grid,
WGP mode). Point it at WGP 3 (the only one that emits instruction tokens here) and launch enough workgroups
that CU 3 gets some (`examples/saxpy.hip` launches 192):

```bash
hipcc --offload-arch=gfx1100 -O3 examples/saxpy.hip -o .work/att/saxpy
rocprofv3 --att --att-target-cu 3 --att-shader-engine-mask 0x1 \
    --att-library-path <dir of AMD's rocprof-trace-decoder library> -d .work/att/run -- .work/att/saxpy
tools/from-att.sh .work/att/run .work/att/saxpy_att      # .att files unchanged + pcmap of code object 2
build/wavewait .work/att/saxpy_att --causes --top 10
```
`tools/att-capture.sh RUNDIR -- CMD...` is that capture without the traps: CU 3 / SE mask 0x1 / the decoder path as defaults
(`ATT_CU`, `ATT_SE_MASK`, `ATT_DECODER_DIR`, `ATT_KERNEL` regex), a 256 MB buffer (`ATT_BUFFER`; more needs `ATT_BUFFER_OK=1`:
at 1 GB rocprofv3 fails to create the ATT packet and then deadlocks in its signal handler, holding the GPU for minutes), `timeout -s KILL`
(`ATT_TIMEOUT`, 300 s) and a watcher that kills the whole process group within about a second of `failed to create ATT packet` or
`Resource deadlock` in the log and exits `FAIL att: ...`. Afterwards it prints the biggest trace against the buffer and warns
(`WARN`) from 90 %: probably cut. It runs itself under `gpu-wait run` when that is installed. Then `build/wavewait app RUNDIR`.
Checked: the saxpy table has the same 28 instructions in the same order as the reference capture
(`fixtures/saxpy_cu`, a one-workgroup launch), 8 waves per instruction instead of 4 (two workgroups on CU 3). A single-workgroup
launch traces nothing: it runs on whichever CU the dispatcher picks.

A walk with `mism` > 0 prints `FAIL walk` and exits 3: its causes look valid and are not (`--allow-mism` shows them, with `WARN`).

## A code object without a host program: `tools/run_hsaco`

`tools/run_hsaco KERNEL.hsaco SYMBOL GRID BLOCK [BYTES|iN ...]` launches one kernel of a gfx1100 code object (hipcc, Mojo,
hand asm) through the HIP runtime (`tools/run_hsaco.mojo`, loaded at run time, built into `build/` on first use). `GRID` and
`BLOCK` are `x[,y[,z]]`; each further argument is a device buffer of that many bytes (filled with 1.0f) or `iN`, an int32 value,
in kernel order. The runtime fills the hidden kernargs (blockDim, gridDim). It prints the first 4 floats of every buffer.
Under ATT it is an ordinary HIP program:

```bash
hipcc --offload-arch=gfx1100 --cuda-device-only --no-gpu-bundle-output -O3 -c k.hip -o k.hsaco     # WGP mode, as is
tools/att-capture.sh .work/att/k -- tools/run_hsaco k.hsaco kernel_symbol 192 256 4096 4096 4096   # 192+ workgroups: see Limits
tools/from-att.sh .work/att/k .work/att/k_att
build/wavewait .work/att/k_att --causes --top 10      # or: build/wavewait app .work/att/k
```

Reading the table: in the raw table a wait's cost shows on the instruction that issues AFTER it (an
`s_waitcnt vmcnt(0)` that waited 670 cycles shows as a 670 delta on the next instruction); `--causes` fixes that.

## Alignment

Each packet's class (VALU, SALU, SMEM, branch, memory, barrier, IMMEDIATE) must fit the instruction it is
assigned to; an instruction no packet fits is untraced and skipped (seen: `s_delay_alu` always, `s_clause`
sometimes traced as IMMEDIATE, `s_endpgm` never). Packets that fit nothing print a WARN. Disassembly uses the
system LLVM 23: ROCm 7.2's objdump prints some gfx11 VOP3 as `.long` and shifts every later pc.

## Subcommands and outputs

| command | what | check.sh |
|---|---|---|
| `wavewait DIR [--top N] [--causes]` | per-instruction stall table, causes. `--top N` cuts an app-dispatch or `--causes` table to the N costliest rows (charged cycles, costliest first) and ends on the cause summary; the plain table of a capture dir stays whole, `--top N` there sizes the ranking below it; `--top 0` prints every row | golden table, cycles conserved, `app --top 3` prints 3 rows |
| `wavewait rank RUNDIR [--top N]` | every kernel of a whole process from rocprofv3 `--kernel-trace --output-format csv`: share, ms, dispatches, avg us, `mid` (the iteration for a warm `--kernel-iteration-range` capture); PyTorch recipe: `docs/pytorch.md` | total against python's csv sum, quoted C++ names |
| `wavewait diff A B [--json]` | two captures aligned by instruction text (LCS): per-row delta, cause shift, +/- rows, total cycles | 28/28 aligned, 1 removed row flagged |
| `wavewait diff RUN_A RUN_B --kernel K [--top N] [--by-class]` | the same for ONE dispatch of two rocprofv3 ATT run dirs (`--kernel PREFIX` or `--dispatch N`, one selector for both sides). Rows are the N (default 20, `--top 0` = all) that moved the most total cycles (`dcycles`), then the class table, the cause table (cycles A, B, shift) and `total cycles A -> B`. Above 4M cells (`WAVEWAIT_ALIGN_CELLS`) the alignment is Hirschberg's, linear in memory: a 14,000-row kernel diffs in 10 s and 88 MB where the table took 1.2 GB | run dir against itself moves 0 cycles, both alignments agree |
| `wavewait DIR --json` | rows + totals, stable keys, for scripts and agents | round-trips 28 rows |
| `wavewait DIR --by-class` | charged cycles, share and issues per wave per instruction class: vmem load (`global_/buffer_/tbuffer_/flat_/scratch_load*`), vmem store (stores and atomics), smem (`s_load*`, `s_buffer_load*`), lds (`ds_*`), `s_waitcnt` split by counter (vmcnt, lgkmcnt, expcnt, vscnt, depctr, mixed = more than one counter), valu (`v_*`), salu (every other `s_*`, so `s_nop`, `s_clause` and `s_set_inst_prefetch_distance` count here), branch (`s_branch`, `s_cbranch*`), other; `--json` carries the same as `classes`. Cycles are the charged ones and sum to the table total | classes sum to 12897, issues = awk count |
| `wavewait DIR --by-line` | costs per source line (DWARF, build with `-g`) | every pc mapped, addr2line agrees |
| `wavewait DIR --hints` | fix hints from the measured gfx1100 timing (hoist, empty wait, VOPD, LDS bank) and `divergent`: the waves took a branch a different number of times | probe fires all 4, saxpy golden; app_div back edge taken 0..2, silent on uniform kernels |
| `wavewait DIR --exposed [--top N]` | rows by exposed cycles: the traced SIMD's idle cycles, each shared by the waves alive then, so a wait 8 waves sat in together counts once and cycles another wave issued in count not at all; then occupancy (mean, max waves alive) and the waves per SIMD the code object allows | rows + tail = SIMD idle; one wave slot (`WAVEWAIT_ONLY`) gives exposed = cycles - 1 per issue exactly |
| `wavewait DIR --exposed --watts W [--mhs M]` | mining / energy view: the W share spent while the traced SIMD issued nothing, J/MH now and if every idle cycle issued at the same W (an upper bound: an idle SIMD still draws clock and leakage power) | no `--watts` = byte-identical `--exposed` output |
| `wavewait occ CODEOBJ` | per kernel: waves per SIMD it allows and the limit (vgpr, lds, waves), LLVM's rules | 16/16 kernels equal hipcc's `; Occupancy:` (fixtures/occ) |
| `wavewait budget FILE DIR` rule `exposed N` | max exposed cycles | own value passes, -1 fails |
| `wavewait app RUNDIR` | every dispatch of a rocprofv3 ATT run, one row per kernel | 2 kernels, saxpy row = its table (38342) |
| `wavewait app RUNDIR --dispatch N` / `--kernel NAME` | the full table (and every flag below) of ONE dispatch, walked against its own code object | equals its app row |
| `wavewait DIR --loops` | charged cycles per innermost loop (backward branch), poll loops flagged `spin` | cycles conserved on the megakernel fixture |
| `WAVEWAIT_PACKETS=W wavewait ...` | debug: wave W's first 400 packets, the pc each lands on, MISS where the walk lost alignment | - |
| `wavewait budget FILE DIR` | `cycles N` / `cause NAME PCT` rules, exit 1 naming each broken rule | own numbers pass, -1 cycle and -10% fail |
| `wavewait DIR --html OUT` | self-contained per-wave timeline page | 4 lanes x 112 bars |
| `wavewait sim` | blocked: needs the per-SIMD scheduler (`docs/W7-blocked.md`) | exits 2 |

Peak RSS on the 11 MB trace: 24.0 MB table, 24.1 MB `--html`; app mode on `fixtures/app` 45.2 MB.
A 37 MB trace walks in 294 ms at 48.4 MiB (was 579 ms: a List allocated per packet).

## Limits

- The traced SIMD is found from the trace (the one where every instruction packet's wave slot is alive); AMD's
  decoder put `examples/diverge.hip` on SIMD 3. Earlier versions always walked SIMD 0.
- `--exposed` sees one SIMD's issue stream: a cycle counts as hidden when another wave on that SIMD issued. AMD's
  rocprof-compute-viewer ranks pipes instead (WMMA > VALU > VMEM/LDS > SALU); the two numbers are not the same.
- Divergence is wave level only: SQTT on gfx11 has no EXEC mask. `divergent` counts taken branches (op 3); a
  not-taken branch sends op 4, which the walk does not count.
- ATT traces only workgroups that land on CU 3: launch enough of them (a single workgroup traces nothing).
- No emulator replay yet (`wavewait sim`, `docs/W7-blocked.md`).

## Mojo analyzer

`src/wavewait.mojo` (binary `build/wavewait`) decodes raw RDNA3 SQTT itself (a nibble state machine over the layout 3 packet
tables, frozen in `src/sqtt_table.mojo`), no Python at analysis time. `tools/from-att.sh` builds `blob_N.bin` + `pcmap.tsv` from
an ATT run (`llvm-objdump` through `tools/pcmap.awk`). Checked byte-identical against the retired Python analyzer
(`tools/stalls.py`, deleted; its saxpy table is frozen in `fixtures/golden/`) on the saxpy
fixture and 8 probe captures (loops and taken branches included). `--kernel PREFIX` picks another program
(e.g. `probe` for the probe captures).

### `--causes`

Moves each wait's cost onto the `s_waitcnt` / `s_barrier` that held the wave (the next instruction keeps 1
cycle), labels every row (wave start, mem, lds/smem, barrier, depctr, valu dep, lds queue, salu dep, vmem
issue, fetch, issue wait, issue) from the measured gfx1100 timing in the `rdna3-sqtt-emu` skill, and sums the kernel
by cause. Total cycles are conserved (check.sh). saxpy: 27% wave start, 25% lds/smem, 21% mem, 21% mem+lds.

The decoder streams (no packet list): 11 MB trace 72 -> 23 MB peak, of which 11 MB is the trace itself.

## Also here

- `probes/`: 14 hand-written gfx1100 assembly probes (`NAME.s`: LDS, banks, barriers, WMMA, icache, s_nop) that measured
  RDNA3 timing rules. `probes/build.sh [OUTDIR] [NAME...]` assembles them (clang + ld.lld, `PF=1..3` arms icache's prefetch
  distance); `probes/verify.sh` (in `check.sh`) checks every probe's code bytes, disassembly and kernel descriptor against
  `probes/golden/`, the streams they had before they were assembly. Capture one with the launch line in its header, e.g.
  `tools/att-capture.sh RUN -- tools/run_hsaco build/probes/bank.hsaco bank 192 32 128`; the grid must reach CU 3 (see Limits).
- `tools/att-capture.sh`: the rocprofv3 ATT capture above, guarded (buffer cap, hang watcher, truncation warning).
- `tools/run_hsaco`: launches one kernel of a code object through HIP, for the capture above.

## Check

`./check.sh` (CPU only): `tools/amd_oracle.py` checks every ATT fixture against AMD's own decoder (`code.json`): hits
equal waves on every pc, each `s_waitcnt` within 1 cycle per wave. stall table of `fixtures/saxpy_cu` is aligned (28 instructions x 4 waves), Mojo == golden, `--causes` conserves cycles.

## For coding agents

Skill folder: [`skills/wavewait/`](skills/wavewait/). CLI reference: [`docs/api.md`](docs/api.md).
Design: [`docs/design.md`](docs/design.md).

[`skills/wavewait/SKILL.md`](skills/wavewait/SKILL.md) teaches an agent the loop: capture with `tools/att-capture.sh`,
find the kernel with `app`, read causes, lines and hints, edit, capture again, `diff`, then lock the win with `budget`.
Copy or symlink the folder into the agent's skills directory (for Claude Code: `~/.claude/skills/wavewait` or a
project's `.claude/skills/wavewait`).

## License

Apache-2.0, see [LICENSE](LICENSE) and [NOTICE](NOTICE). Copyright 2026 AMARBARO · amarbaro.org
labs.

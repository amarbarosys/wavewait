# CLI reference

wavewait is a command line tool, not a library. The binary is `build/wavewait`; `pixi run check` builds it.
Every command prints to stdout. The only file the binary writes is the `--html` page.

## Exit codes

| code | meaning |
|---|---|
| 0 | done |
| 1 | usage error, a `FAIL ...` line (missing input, no matching dispatch, no trace), or a broken `budget` rule |
| 2 | `wavewait sim` (blocked, see `W7-blocked.md`) |
| 3 | `FAIL walk`: the walk lost alignment (`mism` > 0), so the numbers are not trusted. `--allow-mism` prints them anyway, with `WARN` |

An error that Mojo raises (for example an unknown budget rule) prints its message and exits 1.

## Inputs

- **Capture dir** (`DIR`): `blob_N.bin` files and `pcmap.tsv`. `tools/from-att.sh` makes it from a rocprofv3 ATT run.
  `--by-line` and `--json` also read `DIR/codeobj.out`.
- **Run dir** (`RUNDIR`): the `-d` directory of one `rocprofv3 --att` run (`app`, `diff --kernel`, `diff --dispatch`),
  or of one `--kernel-trace --output-format csv` run (`rank`).

## wavewait

### `wavewait [table] DIR [flags]`

One stall table for a capture dir: pc, average and maximum cycles since the wave's previous packet, waves, text.
`table` is optional: `wavewait DIR` does the same. With no argument it prints
`usage: wavewait [table|diff|app|budget] DIR [options]` and exits 1. Output file: none, except `--html`.

Output flags. Use one per run. If you give several, the first in this order wins:
`--html`, `--exposed`, `--loops`, `--hints`, `--by-class`, `--by-line`, `--json`, then the table.

| flag | output |
|---|---|
| `--top N` | rows to print, default 10; `--top 0` prints every row. It cuts an `app` dispatch table and every `--causes` table to the N costliest rows and ends on the cause summary. The plain table of a capture dir stays whole; N there sizes the ranking below it |
| `--causes` | moves each wait's cost onto the `s_waitcnt` or `s_barrier` that held the wave and labels each row with a cause. Total cycles stay the same |
| `--json` | rows, totals, causes and classes as JSON with stable keys |
| `--by-class` | charged cycles, share and issues per wave, per instruction class |
| `--by-line` | cost per source line (DWARF; build the kernel with `-g`) |
| `--hints` | fix hints from the measured gfx1100 timing: hoist, empty wait, VOPD pair, LDS bank, and `divergent` |
| `--exposed` | rows by exposed cycles (the traced SIMD's idle cycles), then occupancy. Uses `--top` |
| `--loops` | charged cycles per innermost loop; a poll loop is flagged `spin`. Uses `--top` |
| `--html OUT` | writes a self-contained per-wave timeline page to `OUT` (at most 64 lanes) and prints `wrote OUT (N lanes, M bars)` |
| `--allow-mism` | print a walk with `mism` > 0 (with `WARN`) instead of `FAIL walk` and exit 3 |

Warnings printed after a table: `WARN N packets matched no instruction class` (alignment suspect) and
`WARN N of M waves never ended` (the trace stopped early; the totals cover only the part it holds).

### `wavewait app RUNDIR`

One summary row per dispatch of a rocprofv3 ATT run: kernel, cycles, waves, top cause, `open`, `mism`, dispatch number.
Exit 1 with `FAIL app: no dispatch in RUNDIR`. Exit 3 if any dispatch has `mism` > 0 (unless `--allow-mism`).

### `wavewait app RUNDIR (--dispatch N | --kernel PREFIX) [flags]`

The full analysis of one dispatch, walked against its own code object. Takes every output flag above.
`--kernel` matches the start of the kernel name as `app` prints it. The selector must match exactly one dispatch;
otherwise `FAIL app: N dispatches match (want exactly 1; add --dispatch N)` and exit 1.

### `wavewait rank RUNDIR [--top N] [--stages FILE]`

Every kernel of a whole process, from the `*_kernel_trace.csv` of a `rocprofv3 --kernel-trace --output-format csv` run:
share, ms, dispatches, average us, and `mid` (the iteration to give `--kernel-iteration-range` for a warm capture).
Default `--top 20`. `--stages FILE` adds per-stage rows from a stage file that `tools/comfy_stages.py` writes.
Exit 1 with `FAIL rank: ...` when `RUNDIR` has no `*_kernel_trace.csv`, a csv lacks `Kernel_Name`, `Start_Timestamp` or
`End_Timestamp`, or the stage file is empty. Recipe: `pytorch.md`.

### `wavewait diff A B [--top N] [--by-class] [--json]`

Two capture dirs, aligned by instruction text (LCS): per-row delta, cause shift, `+` and `-` rows, total cycles.
Prints every row unless `--top N` is given. `--json` prints the same as JSON.

### `wavewait diff RUN_A RUN_B (--kernel PREFIX | --dispatch N) [--top N] [--by-class] [--json]`

The same for one dispatch of two ATT run dirs; one selector for both sides. Prints the N rows that moved the most
cycles (`dcycles`; default 20, `--top 0` = all), the class table (with `--by-class`), the cause table (cycles A, B,
shift) and `total cycles A -> B`. Above 4M cells the alignment is Hirschberg's, which needs linear memory;
`WAVEWAIT_ALIGN_CELLS` changes that limit. With fewer than two dirs it prints
`usage: wavewait diff A B [--kernel PREFIX | --dispatch N] [--top N] [--by-class] [--json]` and exits 1.
Exit 3 on a walk with `mism` > 0.

### `wavewait budget FILE DIR`

Gate a capture. `FILE` holds one rule per line; `#` starts a comment:

```
cycles N          # max total charged cycles
exposed N         # max exposed cycles
cause NAME PCT    # max share of one cause in percent; NAME may contain spaces
```

For each broken rule it prints `OVER <rule> (have N)`, then exits 1. When no rule breaks it prints
`ok budget: N cycles within FILE` and exits 0. An unknown rule raises `budget: unknown rule ...` (exit 1).
Exit 3 on a walk with `mism` > 0.

### `wavewait occ CODEOBJ`

One line per kernel of a code object: `N limit name`. `N` is the waves per SIMD the kernel allows; `limit` is
`vgpr`, `lds` or `waves` (LLVM's rules). Exit 0.

### `wavewait sim`

Blocked. Prints a message and exits 2.

## Environment variables of wavewait

| variable | effect |
|---|---|
| `WAVEWAIT_ALIGN_CELLS` | cell count above which `diff` uses the linear-memory alignment (default 4194304) |
| `WAVEWAIT_PACKETS=W` | debug: print wave W's first 400 packets and the pc each lands on; `MISS` marks lost alignment |
| `WAVEWAIT_ONLY=W` | check: walk one wave slot only |

## Scripts

| command | one line | exit | output files |
|---|---|---|---|
| `tools/att-capture.sh RUNDIR -- CMD [ARGS...]` | a guarded `rocprofv3 --att` capture of CMD: buffer cap, hang watcher, timeout | 0 ok; 1 `FAIL att: ...`; 2 usage | `RUNDIR` (new or empty) and `RUNDIR.log` |
| `tools/from-att.sh RUNDIR OUT [CODE_OBJECT_ID]` | turn an ATT run into a capture dir; code object id defaults to 2 | 0 ok; 1 `FAIL att` or `FAIL code object` | `OUT/blob_N.bin`, `OUT/pcmap.tsv` |
| `tools/run_hsaco KERNEL.hsaco SYMBOL GRID BLOCK [BYTES\|iN ...]` | launch one kernel of a gfx1100 code object through HIP. `GRID` and `BLOCK` are `x[,y[,z]]`; a number is a device buffer of that many bytes (filled with 1.0f); `iN` is an int32 value | 0 ok; 1 `FAIL ...`; 2 usage | none (prints the first 4 floats of each buffer) |
| `tools/doctor.sh` | one line per need: binary built, `llvm-objdump`, `rocprofv3`, decoder library, `/dev/kfd`, a gfx1100 GPU | 0 all ok; 1 any `FAIL` | none |
| `tools/att-audit.sh RUNDIR...` | re-walk ATT runs and compare each dispatch with AMD's decoder (`OLD=path` adds an older binary's cycles) | 0 ok; 1 any failure | none |
| `tools/perf-receipt.sh RUNDIR...` | wall time and peak RSS of `app` per run dir | 0 ok; 1 no binary | none |
| `tools/torch-e2e.sh [PYTHON]` | the PyTorch recipe of `pytorch.md` on the GPU | 0 ok; 1 `FAIL ...` | `.work/pt/e2e` |
| `probes/build.sh [OUTDIR] [NAME...]` | assemble the probes to `.hsaco` (`PF=1..3` sets icache's prefetch distance; `LLVM=dir` picks clang and ld.lld) | 0 ok; 1 `FAIL build` | `OUTDIR/NAME.{o,hsaco,err}`, default `build/probes` |
| `probes/verify.sh` | build every probe and compare with `probes/golden/` | 0 ok; 1 any `FAIL` | `.work/probes-build` (`OUT=dir` changes it) |
| `./check.sh` | the CPU-only gate, also `pixi run check` | 0 pass; 1 `FAIL ...` | `.work/check.ok` receipt |

`att-capture.sh` environment: `ATT_CU` (default 3), `ATT_SE_MASK` (0x1), `ATT_DECODER_DIR`, `ATT_BUFFER` (bytes;
above 256 MB needs `ATT_BUFFER_OK=1`), `ATT_TIMEOUT` (300 s), `ATT_KERNEL` (a kernel-name regex), `ATT_ROCPROF`,
`ATT_EXTRA` (more rocprofv3 flags), `ATT_SLIM=1` (delete AMD's decoded per-wave JSON after the capture),
`ATT_NO_GPU_WAIT` (skip the `gpu-wait` wrapper).

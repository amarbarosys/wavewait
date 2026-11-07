---
name: wavewait
description: Per-instruction stall profiling of a gfx1100 (RX 7900 XTX) GPU kernel from a real SQTT thread trace. Capture with rocprofv3 ATT, then rank the kernels of a process, print a stall table with causes, source lines and hints, diff two captures, gate a cycle budget, and write an HTML wave timeline. Use when a kernel on the 7900 XTX is slower than expected, before and after every kernel edit, or to gate kernel performance in a check.
---

# wavewait

Measured, not modelled: which instruction each wave waited on, for how many cycles, and why.
`README.md` has the command table, `docs/api.md` every flag and exit code, `docs/design.md` the data flow.

## When to use

- A kernel on the 7900 XTX is slower than its roofline or than a reference kernel.
- Before and after every kernel edit. Judge the edit by `diff`, not by end-to-end time alone.
- To keep a win: put a `budget` file in the kernel repo's check.

Not for CPU kernels (use `perf`), other GPUs (gfx1100 only), or a noisy machine (fix the clocks first).

## Install from a clone

```bash
git clone https://github.com/amarbarosys/wavewait && cd wavewait
pixi run check            # builds build/wavewait, then runs the CPU-only gate
tools/doctor.sh           # what this machine still needs to capture, with the fix
```

Needs Mojo (pinned in `pixi.toml`), system `/usr/bin/llvm-objdump`, `llvm-dwarfdump` on `PATH`, and for captures
ROCm's `rocprofv3` plus AMD's `librocprof-trace-decoder.so` (`ATT_DECODER_DIR`). Copy or symlink `skills/wavewait`
into the agent's skills directory.

## The 5 commands

```bash
# 1. capture (192+ workgroups: only CU 3 is traced); writes RUNDIR and RUNDIR.log
tools/att-capture.sh .work/att/run -- ./my_app
# 2. which kernel (one row per traced dispatch)
build/wavewait app .work/att/run
# 3. where and why: stall table with causes, then source lines and hints
build/wavewait app .work/att/run --dispatch 1 --causes --top 10
build/wavewait app .work/att/run --dispatch 1 --by-line        # kernel built with -g
build/wavewait app .work/att/run --dispatch 1 --hints
# 4. after the edit, capture again and diff the one dispatch
build/wavewait diff .work/att/run .work/att/run2 --dispatch 1
# 5. lock the win
build/wavewait budget kernel.budget .work/att/k     # k = tools/from-att.sh RUNDIR OUT; exit 1: OVER <rule> (have N)
```

A budget file holds `cycles N`, `exposed N` and `cause NAME PCT` lines. For a whole process (PyTorch, an engine),
run `rocprofv3 --kernel-trace --output-format csv`, then `build/wavewait rank RUNDIR` to pick the kernel and the
iteration (`mid`) for `--kernel-iteration-range`. See `docs/pytorch.md`.

A code object with no host program: `tools/att-capture.sh RUN -- tools/run_hsaco k.hsaco SYMBOL 192 256 4096 4096`.

## Gotchas

- **One workgroup traces nothing.** ATT sees only workgroups that land on CU 3. Launch 192 or more.
- **Read `mism` and the `WARN` lines before any verdict.** A walk that lost alignment prints a confident table.
  wavewait exits 3 with `FAIL walk`; `--allow-mism` shows it anyway. `open` > 0 means the trace stopped early.
- **Raw table versus `--causes`.** In the raw table a wait's cost shows on the instruction after it. `--causes`
  moves it onto the `s_waitcnt` or `s_barrier` that held the wave. Cycles stay the same.
- **A hint is a lead, the diff after the edit is the verdict.**
- **The first dispatch of a kernel runs at cold clocks.** Run a second of other GPU work first, or trace a later
  dispatch with `ATT_EXTRA="--kernel-iteration-range [N-N]"`.
- **Do not raise `ATT_BUFFER` above 256 MB.** rocprofv3 fails to create the packet and then hangs the GPU;
  `att-capture.sh` refuses without `ATT_BUFFER_OK=1` and kills a hung capture.
- **Test grids are too small.** A unit-test launch leaves most dispatches with 0 waves on CU 3. Profile a
  bench-sized launch.
- **`--by-line` needs `-g`** on the kernel build.
- **Several dispatches in one `from-att.sh` capture dir are merged.** Prefer `app RUNDIR --dispatch N`.
- **`wavewait sim` is blocked** (exit 2). There is no prediction without the GPU.
- Peak memory is small (24 MB on an 11 MB trace), but `--by-line` starts an `llvm-dwarfdump` child.

## Gate

```bash
rm -f .work/check.ok; pixi run check     # CPU only; prints "ok wavewait: ..." and exits 0
```

The check keeps a receipt in `.work/check.ok` per tree and Mojo version. Delete it to force a re-run.

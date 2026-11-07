# Design

wavewait answers one question: which instruction did each wave wait on, for how many cycles, and why.
It reads a real SQTT thread trace from the 7900 XTX (gfx1100). It does not model the chip.

## Data flow

```
rocprofv3 --att ──► RUNDIR/*.att (raw SQTT) + code objects + code.json
                      │
        tools/from-att.sh            wavewait app RUNDIR
        (blob_N.bin + pcmap.tsv)     (reads RUNDIR as it is)
                      └────────┬───────────┘
                               ▼
        trace.mojo: decode packets, walk each wave against the disassembly
                               ▼
                    row.mojo: ONE Row record (a traced instruction, summed over waves)
                               ▼
   table · --causes · --by-class · --by-line · --hints · --exposed · --loops · --json · --html · diff · budget
```

- `sqtt_table.mojo` holds the layout 3 packet tables. The stream is a nibble state machine: a 256-entry table gives
  the opcode, then per-opcode tables give length, timestamp field and kind. The tables are hand-edited; no generator.
- `trace.mojo` finds the traced SIMD from the trace (the one where every instruction packet's wave slot is alive),
  builds the code map from `llvm-objdump` output, and walks each wave. A packet's class (VALU, SALU, SMEM, branch,
  memory, barrier, immediate) must fit the instruction it lands on. Instructions that no packet fits are skipped.
- Every output reads the Row record. `classes.mojo`, `hints.mojo`, `loops.mojo`, `lines.mojo`, `html.mojo`,
  `diff.mojo` and `rank.mojo` never touch the decoder.
- `app.mojo` builds the code map per dispatch from that dispatch's own code object, so a run with many kernels needs
  no merge step.

## Memory model

- The decoder streams. It keeps no packet list: an 11 MB trace peaks at 23 MB, of which 11 MB is the trace itself
  (72 MB with a list). A `List` allocated per packet doubled the walk time of a 37 MB trace (579 ms, now 294 ms).
- `diff` keeps an LCS table below 4M cells. Above that it uses Hirschberg's recursion, which needs memory linear in
  the rows: a 14,000-row kernel diffs in 10 s and 88 MB where the table took 1.2 GB.
- `--by-line` starts one `llvm-dwarfdump` child process. It costs its own memory, so plain tables do not start it.
- `--causes` charges waits to the `s_waitcnt` that held them but never creates cycles: both views sum to the same
  total, and `check.sh` asserts it.

## Decisions

- **A wrong walk is an error.** A walk with `mism` > 0 prints plausible causes that are wrong, so the tool exits 3
  unless `--allow-mism` asks for the output.
- **System LLVM, not ROCm's.** ROCm 7.2's `llvm-objdump` prints some gfx11 VOP3 as `.long`, which shifts every
  later pc. The tool calls `/usr/bin/llvm-objdump`.
- **No capture path of our own.** `rocprofv3 --att` writes raw RDNA3 SQTT for any HIP program. `att-capture.sh`
  only adds guards (buffer cap, hang watcher, timeout). `tools/run_hsaco` launches a bare code object so that it
  is an ordinary HIP program under ATT.

## Rejected

- **A Python analyzer.** The Mojo walk matches the retired Python one byte for byte on the saxpy fixture and eight
  probe captures. Its saxpy table is frozen in `fixtures/golden/`; the Python code is gone.
- **Walking SIMD 0 always.** Wrong on loops: the traced SIMD can be another one. It is found from the trace now.
- **Reading NEW_PC as 72 bits.** AMD's decoder reads it as 64. At 72 bits the stream desyncs and produces bogus
  timestamp deltas of up to 3.7e10 cycles (`sqtt_table.mojo`).
- **A what-if simulator (`wavewait sim`).** Fitted constants failed off-fit. A cycle-stepped per-SIMD scheduler is
  needed first, and it does not exist (`W7-blocked.md`).

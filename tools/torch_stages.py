"""Stage markers for a PyTorch job, in the --stages format of `wavewait rank` (same as comfy_stages.py):
ns (CLOCK_BOOTTIME, rocprofv3's kernel-trace clock), event, id, label. Each mark synchronizes the GPU first,
so a stage owns exactly the kernels launched inside it.

    sys.path.insert(0, os.path.expanduser("~/Projects/mojo/wavewait/tools"))
    from torch_stages import Stages
    st = Stages()                      # path from $WW_STAGES; no env -> every call is a no-op
    for step in range(n):
        st.mark("fwd", step); ...; st.mark("bwd", step); ...; st.mark("opt", step); ...
    st.end()
    # WW_STAGES=$PWD/stages.tsv rocprofv3 --kernel-trace --output-format csv --preload librocprofiler-sdk.so -d RUN -- python job.py
    # wavewait rank RUN --stages stages.tsv  -> one row per stage: wall, GPU busy, idle, top kernel

Gotcha: the sync makes stages honest but costs a little wall time; profile with it, train without it.
rank prints one row per stage, so mark the phases of a few steps, not of a whole run.
"""
import os
import time


class Stages:
    def __init__(self, path: str | None = None):
        path = path or os.environ.get("WW_STAGES")
        self.f = open(path, "w") if path else None
        self.n = 0
        if self.f:
            self._line("execution_start", "", "")

    def _line(self, event, node, label):
        print(time.clock_gettime_ns(time.CLOCK_BOOTTIME), event, node, label, sep="\t", file=self.f, flush=True)

    def _sync(self):
        import torch

        torch.cuda.synchronize()

    def mark(self, label: str, step: int | str = ""):
        if not self.f:
            return
        self._sync()
        self.n += 1
        self._line("executing", str(step) if step != "" else str(self.n), label)

    def end(self):
        if not self.f:
            return
        self._sync()
        self._line("execution_success", "", "")
        self.f.close()
        self.f = None

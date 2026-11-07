# run_hsaco KERNEL.hsaco SYMBOL GRID BLOCK [ARG ...]: launch ONE kernel of a gfx1100 code object (hipcc, Mojo, hand asm)
# through the HIP runtime, so rocprofv3 --att sees it as an ordinary HIP program (tools/att-capture.sh RUN -- tools/run_hsaco ...).
#   GRID, BLOCK  x[,y[,z]]: workgroups, threads per workgroup
#   ARG          a number = the byte size of a device buffer (filled with 1.0f), `iN` = an int32 value; in kernel order
# Hidden kernargs (blockDim, gridDim) are filled by the runtime from the code object metadata. Prints the first 4 floats of
# every buffer after the kernel ran. ATT traces only workgroups that land on CU 3: use a grid of 192 or more.
# Built on demand by tools/run_hsaco (the wrapper); HIP is loaded at run time, nothing links to ROCm.
from std.ffi import OwnedDLHandle
from std.sys import argv, exit


def fail(step: String, why: String):
    print("FAIL " + step + ": " + why)
    exit(1)


def usage():
    print("usage: run_hsaco KERNEL.hsaco SYMBOL GRID BLOCK [BYTES|iN ...]   (GRID, BLOCK = x[,y[,z]])")
    exit(2)


def dims(s: String, what: String) -> List[Int]:
    var d = List[Int](length=3, fill=1)
    var parts = s.split(",")
    if len(parts) > 3:
        fail("args", what + " '" + s + "' has more than 3 dimensions")
    for i in range(len(parts)):
        try:
            d[i] = Int(String(parts[i]))
        except:
            fail("args", what + " '" + s + "' is not x[,y[,z]]")
        if d[i] < 1:
            fail("args", what + " '" + s + "' has a dimension below 1")
    return d^


def check(lib: OwnedDLHandle, rc: Int32, what: String):
    if rc != 0:
        var c = Int(rc)
        var name = String("hipError")
        if c == 1:
            name = "hipErrorInvalidValue"
        elif c == 2:
            name = "hipErrorOutOfMemory"
        elif c == 100:
            name = "hipErrorNoDevice"
        elif c == 209:
            name = "hipErrorNoBinaryForGpu (the code object is not gfx1100)"
        elif c == 500:
            name = "hipErrorNotFound (no such kernel symbol)"
        fail("hip", what + ": " + name + " " + String(c))


def main() raises:
    var av = argv()
    if len(av) < 5:
        usage()
    var path = String(av[1])
    var symbol = String(av[2])
    var grid = dims(String(av[3]), "GRID")
    var block = dims(String(av[4]), "BLOCK")
    # every argument is parsed before HIP is touched: a typo costs no GPU time
    var n = len(av) - 5
    var is_int = List[Bool]()
    var val = List[Int]()
    for i in range(n):
        var a = String(av[5 + i])
        var isi = a.startswith("i")
        var num = String(a[byte = 1:]) if isi else a
        try:
            var v = Int(num)
            if v < 1 and not isi:
                fail("args", "buffer size '" + a + "' must be a positive byte count")
            if not isi and v % 4 != 0:
                fail("args", "buffer size '" + a + "' is not a multiple of 4")
            is_int.append(isi)
            val.append(v)
        except:
            fail("args", "argument '" + a + "' is neither a byte size nor iN")
    var image: List[UInt8]
    try:
        with open(path, "r") as f:
            image = f.read_bytes()
    except:
        fail("file", "cannot read " + path)
        return
    if len(image) < 4 or image[0] != 0x7F or image[1] != 0x45 or image[2] != 0x4C or image[3] != 0x46:
        fail("file", path + " is not an ELF code object")

    var hip = OwnedDLHandle("libamdhip64.so")
    check(hip, hip.call["hipInit", Int32](Int32(0)), "hipInit")
    var module = UInt64(0)
    check(hip, hip.call["hipModuleLoadData", Int32](Int(Pointer(to=module)), Int(image.unsafe_ptr())), "hipModuleLoadData " + path)
    var kfn = UInt64(0)
    var sym = symbol.copy()
    check(hip, hip.call["hipModuleGetFunction", Int32](Int(Pointer(to=kfn)), module, Int(sym.unsafe_ptr())), "hipModuleGetFunction " + symbol)

    # one 8-byte slot per kernel argument (a device pointer or an int32 in the low half); params[i] = address of slot i
    var slot = List[UInt64](length=n + 1, fill=0)
    var params = List[UInt64](length=n + 1, fill=0)
    var host = List[List[Float32]]()
    var sizes = List[Int]()
    for i in range(n):
        if is_int[i]:
            slot[i] = UInt64(val[i]) & 0xFFFFFFFF
        else:
            var elems = val[i] // 4
            var buf = List[Float32](length=elems, fill=Float32(1))
            var dev = UInt64(0)
            check(hip, hip.call["hipMalloc", Int32](Int(Pointer(to=dev)), val[i]), "hipMalloc " + String(val[i]))
            check(hip, hip.call["hipMemcpy", Int32](dev, Int(buf.unsafe_ptr()), val[i], 1), "hipMemcpy to device")
            slot[i] = dev
            host.append(buf^)
            sizes.append(val[i])
        params[i] = UInt64(Int(slot.unsafe_ptr()) + 8 * i)
    check(hip, hip.call["hipModuleLaunchKernel", Int32](
        kfn, grid[0], grid[1], grid[2], block[0], block[1], block[2], 0, 0, Int(params.unsafe_ptr()), 0), "hipModuleLaunchKernel " + symbol)
    check(hip, hip.call["hipDeviceSynchronize", Int32](), "hipDeviceSynchronize (kernel " + symbol + ")")

    var b = 0
    for i in range(n):
        if is_int[i]:
            continue
        var out = List[Float32](length=sizes[b] // 4, fill=Float32(0))
        check(hip, hip.call["hipMemcpy", Int32](Int(out.unsafe_ptr()), Int(slot[i]), sizes[b], 2), "hipMemcpy to host")
        var line = String("arg" + String(i) + " out[:4] =")
        for k in range(min(4, len(out))):
            line += " " + String(out[k])
        print(line)
        b += 1
    print("ok run_hsaco: " + symbol + " grid " + String(grid[0]) + "," + String(grid[1]) + "," + String(grid[2]) + " block " + String(block[0]) + "," + String(block[1]) + "," + String(block[2]) + ", " + String(n) + " args")
    # the owners of every raw address handed to HIP live to here
    _ = (len(image), len(slot), len(params), sym.byte_length(), len(host))

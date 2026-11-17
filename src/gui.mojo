# wavewait-gui ARGS: one capture's cycles by cause and its costliest rows in an imkit window; `wavewait ARGS --gui`
# starts it with the same arguments. Close the window to exit. Needs a GPU, and -I ../mojo-imkit/src at build.
from std.collections import List
from std.os import getenv
from std.sys import argv
from max.gpu.host import DeviceContext
from imkit.draw import UW, UH
from imkit.font import Font
from imkit.layer import Layer
from imkit.theme import amarbaro
from imkit.ui import Ui
from imkit.window import Window
from row import Analysis, fmt1, pad
from app import refuse
from wavewait import capture, flag, opt

comptime FW = Float32(UW)
comptime FH = Float32(UH)
comptime HALF = Float32(UW // 2)
comptime ROWS = 22  # rows that fit the right panel
comptime CAUSES = 20  # causes that fit the left panel


def main() raises:
    var args = List[String]()
    for a in argv():
        args.append(String(a))
    var an = capture(args)
    refuse(an, args)
    gui(an, atol(opt(args, "--top", "10"), 10), flag(args, "--causes"))


def gui(ref an: Analysis, top: Int, causes: Bool) raises:
    var grand = max(an.grand, 1)
    # cause bars, largest first
    var keys = List[String]()
    for k in an.by_cause.keys():
        keys.append(k)
    for i in range(1, len(keys)):
        var j = i
        while j > 0 and an.by_cause[keys[j]] > an.by_cause[keys[j - 1]]:
            keys.swap_elements(j, j - 1)
            j -= 1
    # every string is built here: the frame loop allocates nothing between begin() and finish()
    var names = List[String]()
    var shares = List[String]()
    var vals = List[Int]()
    for k in keys:
        names.append(k)
        vals.append(an.by_cause[k])
        shares.append(String(an.by_cause[k] * 100 // grand) + "%")
    # rows ranked by cost (charged cycles with --causes, else the summed delta), costliest first, ties in row order
    var packed = List[Int]()
    for i in range(len(an.rows)):
        var v = an.rows[i].csum if causes else an.rows[i].sum
        packed.append(v * 4194304 + (4194303 - i))
    sort(packed)
    var cells = List[String]()  # per shown row: addr, average, waves, cause, instruction
    var n = min(top, min(len(packed), ROWS))
    for j in range(n):
        ref r = an.rows[4194303 - packed[len(packed) - 1 - j] % 4194304]
        var s = r.csum if causes else r.sum
        cells.append(pad(hex(r.pc), 6))
        cells.append(fmt1(s, r.waves))
        cells.append(String(r.waves))
        cells.append(r.cause)
        cells.append(String(r.text[byte=0:min(60, r.text.byte_length())]))
    var head = List[String]()
    head.append("waves " + String(an.waves) + "   cycles " + String(an.grand) + "   mismatches " + String(an.mismatches))
    head.append("capture " + an.dir)
    var u = Ui(Font(getenv("IMKIT_FONT", "/usr/share/fonts/TTF/Roboto-Medium.ttf"), [13, 16, 22]))
    u.set_theme(amarbaro())
    var ctx = DeviceContext()
    var layer = Layer(ctx, u)
    var win = Window("wavewait " + an.dir, UW, UH, UW, UH)
    var bg = List[UInt32](length=UW * UH, fill=u.theme.panel)
    var bw = Float32(UW // 2 - 290)  # cause bar: name in the first 174 px, percent after it
    var cx = HALF + 24
    var title_right = String("costliest rows by charged cycles") if causes else String("costliest rows by summed delta")
    while True:
        var inp = win.poll()
        if inp.quit:
            break
        u.begin(inp)
        u.panel(16, 16, FW - 16, 128, "wavewait show")
        for i in range(len(head)):
            _ = u.text(32, Float32(56 + 22 * i), head[i], 0, u.theme.text)
        u.panel(16, 144, HALF - 8, FH - 16, "cycles by cause")
        for c in range(min(len(names), CAUSES)):
            var y = 180 + 26 * Float32(c)
            _ = u.text(32, y, names[c], 0, u.theme.text)
            u.rect(190, y + 4, 190 + bw, y + 12, 4, u.theme.surface)
            u.rect(190, y + 4, 190 + bw * Float32(vals[c]) / Float32(grand), y + 12, 4, u.theme.warn if c == 0 else u.theme.accent)
            _ = u.text(200 + bw, y, shares[c], 0, u.theme.text)
        u.panel(HALF + 8, 144, FW - 16, FH - 16, title_right)
        u.clip(HALF + 8, 144, FW - 24, FH - 16)  # long rows stop 8 px inside the border, not on it
        _ = u.text(cx, 184, "pc", 0, u.theme.muted)
        _ = u.text(cx + 80, 184, "avg", 0, u.theme.muted)
        _ = u.text(cx + 150, 184, "n", 0, u.theme.muted)
        _ = u.text(cx + 190, 184, "cause", 0, u.theme.muted)
        _ = u.text(cx + 300, 184, "instruction", 0, u.theme.muted)
        for i in range(n):
            var y = 206 + 22 * Float32(i)
            _ = u.text(cx, y, cells[5 * i], 0, u.theme.text)
            _ = u.text(cx + 80, y, cells[5 * i + 1], 0, u.theme.text)
            _ = u.text(cx + 150, y, cells[5 * i + 2], 0, u.theme.text)
            _ = u.text(cx + 190, y, cells[5 * i + 3], 0, u.theme.accent)
            _ = u.text(cx + 300, y, cells[5 * i + 4], 0, u.theme.text)
        u.unclip()
        u.finish()
        layer.render(u)
        win.present(Int(bg.unsafe_ptr()), Int(layer.pixels.unsafe_ptr()))

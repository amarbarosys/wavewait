# RDNA3 SQTT (thread trace, layout 3) decode tables. Source of truth, frozen: edit by hand, no generator.
# The stream is a sequence of nibbles; a packet's opcode comes from STATE[byte] (a 256-entry nibble state
# machine), and per opcode (index 0..24):
#   NIBS    packet length in nibbles
#   DLO     bit offset of the timestamp delta field in the packet; DMASK its mask
#   SPECIAL 0 plain, 1 TS_DELTA_OR_MARK, 2 TS_DELTA_SHORT
#   KIND    0 other, 1 WAVESTART, 2 WAVEEND, 3 INST, 4 VALUINST, 5 IMMEDIATE, 6 IMMEDIATE_MASK
# NEW_PC (0b0100001) is 16 nibbles (64 bits), as in AMD's own decoder; reading it as 18 nibbles desyncs the
# stream until it falls back in step, after bogus TS_DELTA_OR_MARK deltas of up to 3.7e10 cycles.
comptime STATE: Array[Int, 256] = [16, 22, 24, 1, 5, 11, 12, 16, 15, 20, 24, 1, 9, 4, 3, 2, 16, 23, 24, 1, 6, 8, 13, 16, 15, 20, 24, 1, 10, 4, 3, 2, 16, 7, 24, 1, 5, 11, 12, 16, 15, 20, 24, 1, 9, 4, 3, 2, 16, 14, 24, 1, 6, 8, 13, 16, 15, 20, 24, 1, 10, 4, 3, 2, 16, 16, 24, 1, 5, 11, 12, 16, 15, 20, 24, 1, 9, 4, 3, 2, 16, 17, 24, 1, 6, 8, 13, 16, 15, 20, 24, 1, 10, 4, 3, 2, 16, 18, 24, 1, 5, 11, 12, 16, 15, 20, 24, 1, 9, 4, 3, 2, 16, 21, 24, 1, 6, 8, 13, 16, 15, 20, 24, 1, 10, 4, 3, 2, 16, 22, 24, 1, 5, 11, 12, 16, 15, 20, 24, 1, 9, 4, 3, 2, 16, 23, 24, 1, 6, 8, 13, 16, 15, 20, 24, 1, 10, 4, 3, 2, 16, 7, 24, 1, 5, 11, 12, 16, 15, 20, 24, 1, 9, 4, 3, 2, 16, 14, 24, 1, 6, 8, 13, 16, 15, 20, 24, 1, 10, 4, 3, 2, 16, 16, 24, 1, 5, 11, 12, 16, 15, 20, 24, 1, 9, 4, 3, 2, 16, 17, 24, 1, 6, 8, 13, 16, 15, 20, 24, 1, 10, 4, 3, 2, 16, 19, 24, 1, 5, 11, 12, 16, 15, 20, 24, 1, 9, 4, 3, 2, 16, 21, 24, 1, 6, 8, 13, 16, 15, 20, 24, 1, 10, 4, 3, 2]
comptime NIBS: Array[Int, 25] = [0, 3, 2, 2, 3, 6, 6, 16, 5, 8, 12, 5, 13, 7, 12, 2, 1, 6, 6, 8, 16, 16, 12, 16, 5]
comptime DLO: Array[Int, 25] = [0, 3, 4, 4, 4, 5, 5, 8, 5, 5, 5, 5, 5, 5, 7, 4, 0, 7, 8, 8, 4, 7, 12, 0, 4]
comptime DMASK: Array[Int, 25] = [0, 7, 3, 3, 7, 7, 7, 7, 7, 3, 3, 7, 7, 7, 3, 15, 0, 511, 7, 7, 7, 7, 68719476735, 0, 7]
comptime SPECIAL: Array[Int, 25] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 1, 0, 0]
comptime KIND: Array[Int, 25] = [0, 4, 0, 0, 5, 6, 0, 0, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3]

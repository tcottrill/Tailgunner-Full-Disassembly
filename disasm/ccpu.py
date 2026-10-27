"""Cinematronics CCPU instruction set: decode and encode.

Semantics follow ccpu.cpp (Aaron Giles' core, after Zonn Moore's
documentation). Mnemonics are the ones in that core's comments; the
operand syntax is this disassembly's own:

  LDAI #$300   00-0F  A/B = n<<8 (only the high nibble can be loaded)
  INP  $n      10-1F  A: input bit n (0-15); B: switch bit n&7
  A8I  #$nn    20 nn  acc += nn          A4I #$n  21-2F  acc += n
  S8I  #$nn    30 nn  acc -= nn          S4I #$n  31-3F  acc -= n
  LPAI Lxxxx   4j nn  J = 12-bit target (j | nn&F0 | (nn&0F)<<8)
  T4K          50     PC = bank selected by P, offset J   (also selects B)
  JMIB..JOSB   51-56  conditional jump to J, next instruction uses B
  SSA          57     no-op that selects B for the next instruction
  JMP          58     PC = (bank of PC) + J
  JMI..JOS     59-5E  conditional jump to J
  NOP          5F
  ADD/SUB/LDA/TST/WS/STA $rr   6x 7x Ax Bx Cx Dx  RAM[P<<4 | x]
  SETP $p      8p     P = p (selects RAM page $p0-$pF for the ops above)
  OUT  $n      9n     output latch n = ~A bit 0
  DV IV LPAP WSP LKP MUL NV FRM STAP ADDP CST SUBP ANDP LDAP SHR SHL ASR
  SHRB SHLB    E0-FF  register / RAM[I] operations

The direct-RAM opcodes hold only the low nibble of the address; the high
nibble is the P register. The listing prints the full 8-bit address
($53) where P is known; the encoder keeps the low nibble.

LKP is followed by one byte that the CPU fetches and discards (the
core increments PC after the lookup); it is listed as LKP's operand.

Opcodes $E0-$FF exist in two rows. Where both rows do the same thing the
F-row form gets a trailing 'F' (LKPF, MULF, NVF, FRMF, STAPF, SUBPF,
ANDPF, LDAPF); the shifts differ in the compare value they set, so their
F-row forms are SHRF, SHLF, ASRF, SHRBF, SHLBF.
"""

# Single-byte opcodes $E0-$FF
ROW_E = ["DV", "LPAP", "LKP", "MUL", "NV", "FRM", "STAP", "ADDP",
         "SUBP", "ANDP", "LDAP", "SHR", "SHL", "ASR", "SHRB", "SHLB"]
ROW_F = ["IV", "WSP", "LKPF", "MULF", "NVF", "FRMF", "STAPF", "CST",
         "SUBPF", "ANDPF", "LDAPF", "SHRF", "SHLF", "ASRF", "SHRBF", "SHLBF"]
JUMPS = ["T4K", "JMIB", "JVNB", "JLTB", "JEQB", "JCZB", "JOSB", "SSA",
         "JMP", "JMI", "JVN", "JLT", "JEQ", "JCZ", "JOS", "NOP"]
RAMOPS = {0x6: "ADD", 0x7: "SUB", 0xA: "LDA", 0xB: "TST", 0xC: "WS", 0xD: "STA"}

# operand kinds
IMP, IMM_HI, IMM4, IMM8, PORT, PAGE, RAM, TARGET, SKIP = range(9)

OPS = {}  # mnemonic -> (kind, base opcode)
for i, m in enumerate(ROW_E):
    OPS[m] = (SKIP if m == "LKP" else IMP, 0xE0 + i)
for i, m in enumerate(ROW_F):
    OPS[m] = (SKIP if m == "LKPF" else IMP, 0xF0 + i)
for i, m in enumerate(JUMPS):
    OPS[m] = (IMP, 0x50 + i)
for hi, m in RAMOPS.items():
    OPS[m] = (RAM, hi << 4)
OPS.update({
    "LDAI": (IMM_HI, 0x00), "INP": (PORT, 0x10),
    "A8I": (IMM8, 0x20), "A4I": (IMM4, 0x20),
    "S8I": (IMM8, 0x30), "S4I": (IMM4, 0x30),
    "LPAI": (TARGET, 0x40), "SETP": (PAGE, 0x80), "OUT": (PORT, 0x90),
})

# Jumps that leave the next instruction on the B accumulator
B_SELECT = set(range(0x50, 0x58))
# Unconditional transfers (no fall-through)
UNCOND = {0x50, 0x58}
COND = set(range(0x51, 0x57)) | set(range(0x59, 0x5F))
FRAME = {0xE5, 0xF5}


def length(op):
    if op in (0x20, 0x30) or 0x40 <= op <= 0x4F or op in (0xE2, 0xF2):
        return 2
    return 1


def lpai_target(op, arg):
    """12-bit J value loaded by LPAI (opcode $4j, operand nn)."""
    return (op & 0x0F) | (arg & 0xF0) | ((arg & 0x0F) << 8)


def lpai_encode(j):
    return 0x40 | (j & 0x0F), (j & 0xF0) | ((j >> 8) & 0x0F)


def decode(rom, pc):
    """Return (mnemonic, kind, value, length) for the instruction at pc.

    value: immediate / port / page / RAM low nibble / J target, or the
    discarded byte for LKP.
    """
    op = rom[pc]
    hi, lo = op >> 4, op & 0x0F
    if hi == 0x0:
        return "LDAI", IMM_HI, lo << 8, 1
    if hi == 0x1:
        return "INP", PORT, lo, 1
    if hi in (0x2, 0x3):
        name8, name4 = ("A8I", "A4I") if hi == 0x2 else ("S8I", "S4I")
        if lo == 0:
            return name8, IMM8, rom[pc + 1], 2
        return name4, IMM4, lo, 1
    if hi == 0x4:
        return "LPAI", TARGET, lpai_target(op, rom[pc + 1]), 2
    if hi == 0x5:
        return JUMPS[lo], IMP, None, 1
    if hi in RAMOPS:
        return RAMOPS[hi], RAM, lo, 1
    if hi == 0x8:
        return "SETP", PAGE, lo, 1
    if hi == 0x9:
        return "OUT", PORT, lo, 1
    row = ROW_E if hi == 0xE else ROW_F
    m = row[lo]
    if lo == 2:
        return m, SKIP, rom[pc + 1], 2
    return m, IMP, None, 1


def encode(mnem, value=None):
    """Bytes for one instruction. value is an int (already evaluated)."""
    kind, base = OPS[mnem]
    if kind == IMP:
        return bytes([base])
    if kind == SKIP:
        return bytes([base, value & 0xFF])
    if kind == IMM_HI:
        if value & 0xFF or not 0 <= value <= 0xF00:
            raise ValueError("LDAI value must be $000-$F00 in steps of $100: $%X" % value)
        return bytes([value >> 8])
    if kind == IMM4:
        if not 1 <= value <= 15:
            raise ValueError("%s needs 1-15: %d" % (mnem, value))
        return bytes([base | value])
    if kind == IMM8:
        if not 0 <= value <= 0xFF:
            raise ValueError("%s needs 0-255: %d" % (mnem, value))
        return bytes([base, value])
    if kind in (PORT, PAGE):
        if not 0 <= value <= 15:
            raise ValueError("%s needs 0-15: %d" % (mnem, value))
        return bytes([base | value])
    if kind == RAM:
        return bytes([base | (value & 0x0F)])
    if kind == TARGET:
        a, b = lpai_encode(value & 0xFFF)
        return bytes([a, b])
    raise ValueError(mnem)

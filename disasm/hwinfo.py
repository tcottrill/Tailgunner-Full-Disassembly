"""Tailgunner board I/O as the CCPU sees it.

From the AAE Cinematronics driver (cinematronics_driver.cpp, after MAME's
cinemat.cpp) and the Tailgunner sound board handler (cinematronics_sound.cpp),
in the AAE source (github.com/tcottrill/AAE: drivers/, sndhrdwr/).
"""

# INP n with the A accumulator reads bit n of the INPUTS port (active low)
INPUTS = {
    5: ("IN_FIRE", "fire button (active low)"),
    6: ("IN_SHIELD", "shield button (active low)"),
    7: ("IN_START", "start button (active low)"),
}

# INP n with the B accumulator reads switch n; the board wires the DIP
# switches to the CCPU switch inputs in the order 2,5,4,3,0,1,6,7 (MAME's
# switch_shuffle). Bits named as in the MAME/AAE port definition.
SWITCHES = {
    0: ("SW_COINAGE", "DIP bit 2: coinage, 1 = 1 coin 1 credit, 0 = 2 coins 1 credit"),
    1: ("SW_SHIELD_HI", "DIP bit 5: shield points, high bit (with SW_SHIELD_LO0/LO1)"),
    2: ("SW_UNK_4", "DIP bit 4: unknown in MAME"),
    3: ("SW_UNK_3", "DIP bit 3: unknown in MAME"),
    4: ("SW_SHIELD_LO0", "DIP bit 0: shield points, low bit 0"),
    5: ("SW_SHIELD_LO1", "DIP bit 1: shield points, low bit 1"),
    6: ("SW_UNK_6", "DIP bit 6: unknown in MAME"),
    7: ("SW_COIN", "coin latch: 0 once a coin has dropped, until OUT 5 resets it"),
}

# OUT n writes the inverse of bit 0 of A to output latch n
OUTPUTS = {
    0: ("OUT_SND_A0", "sound latch address bit 0"),
    1: ("OUT_SND_A1", "sound latch address bit 1"),
    2: ("OUT_SND_A2", "sound latch address bit 2"),
    3: ("OUT_SND_DATA", "sound latch data bit"),
    4: ("OUT_SND_STROBE", "sound strobe: the falling edge writes DATA into sound bit A2-A0"),
    5: ("OUT_COIN_RESET", "coin latch reset: the rising edge of the latch input (A bit 0 going 1 -> 0) clears it"),
    6: ("OUT_INTENSITY", "vector intensity: A bit 0 = 1 bright, 0 dim"),
    7: ("OUT_MUX", "joystick multiplexer: A bit 0 = 0 selects the x axis for JMI, 1 the y axis"),
}

# the sound board's 8-bit register written through OUT 0-4 (bit = 0 turns a sound on)
SOUND_BITS = {
    0: "explosion",
    1: "rumble",
    2: "laser",
    3: "shield",
    4: "bounce",
    5: "hyperspace",
}


def inp_note(n, acc):
    if acc == 2:
        nm, desc = SWITCHES[n & 7]
        return "switch %d: %s" % (n & 7, desc)
    if n in INPUTS:
        return "input %d: %s" % (n, INPUTS[n][1])
    return "input %d: not wired on Tailgunner (reads 1)" % n


def out_note(n):
    return OUTPUTS[n & 7][1] if n < 8 else "output %d" % n

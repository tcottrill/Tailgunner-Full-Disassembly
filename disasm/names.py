"""Names and descriptions written for this disassembly.

Tailgunner's source code is not known to survive, so every name here was
chosen by reading the code and watching it run (trace/tgtrace.exe); none
is Cinematronics'. Where a meaning rests on something other than the code
itself (a RAM snapshot diff, a captured frame) the description says so.

LABELS  addr -> (NAME, description)   routine / table / branch-target names
RAM     addr -> (NAME, description)   data RAM words ($00-$FF, 12 bits each)
NOTES   addr -> comment               end-of-line remarks on single lines
BLOCKS  addr -> [lines]               comment blocks printed above a line
"""

LABELS = {
    # ------------------------------------------------------------ bank 0
    0x0000: ("RESET", "Power-on and watchdog reset entry. The CCPU starts here with every "
             "register zero. Clears RAM $01-$FF, resets the coin latch, then reads the shield DIP switches."),
    0x0008: ("CLRRAM", ""),
    0x0026: ("INIT2", "Power-on, part 2: shield points from the DIP setting, random seeds, player state cleared; "
             "START held at power-on branches to the test pattern (TESTMODE)."),
    0x0046: ("TESTMODE_GO", ""),
    0x004A: ("WAVEDELAY", "Between waves: WAVE_TIMER counts up to $24 frames (the hyperspace sound starts at 5), then goes to 0 so the next pass starts a new wave."),
    0x0058: ("MAINLOOP", "Top of the frame: the beam to the centre, then FRM waits for the frame timer. One pass, "
             "in order: SNDOFF (attract) / PASSCHK, STARS, ENDPASS (waves, title), MOVEFTR, SHIELDS, FTRCLOSE, "
             "JOYSTICK, CROSSHAIR (fire), FIGHTER1, XHAIRDRAW, LASERS, FIGHTER2, LASERL, FIGHTER3, LASERR, "
             "AFTERFTR; then bank 1: DRAWFTRS, DRAWHUD (score, shields, coins), the attract / start screens, "
             "and back here."),
    0x006E: ("WAITFRM", ""),
    0x0078: ("SNDOFF", "In attract (FTRS_LEFT = 0) every sound is turned off."),
    0x00BE: ("PASSCHK", "Per fighter: an explosion that has run its course (FTRn_STATE past $17) is removed; a "
             "fighter in play nearer than z = $115 has got past and is removed - with a game on FTRS_LEFT goes "
             "down by one, the pass flash starts and WAVE_TIMER (hyperspace) is stepped."),
    0x0143: ("STARS", "Star field, 16 stars ($A0-$BF, x and y). Star coordinates are twice the screen's, the centre at ($408, $308). Each frame every star moves 1/32 of its distance toward the centre (the view is backward, from the tail, so stars run in from the edges; checked on two captured frames: all 16 move inward). In hyperspace (WAVE_TIMER 4 and up) the step is multiplied up and the stars are bright. A star is a dot whose brightness comes from its distance band (STARBRT); one that reaches the centre or leaves the range restarts at the next STARPOS point plus a random offset."),
    0x0148: ("STARLP", ""),
    0x020F: ("NEWSTAR", "Restart a star out at the next STARPOS point (STAR_SLOT); the offset comes from "
             "ROM bytes read at the walking pointer STAR_SEED."),
    0x0267: ("STARBRT", "Star brightness ramp: the vector shift (T) for each distance band."),
    0x0276: ("STARPOS", "Star restart positions: pairs of signed bytes ($80 = 0)."),
    0x0308: ("MOVEFTR", "Fighter motion: each live fighter (page 3, 4, 5) moves by its speed until its "
             "position passes the limit, when it is cleared."),
    0x0339: ("SHIELDS", "Shields: while the shield button is held and shield points remain, the shield is drawn "
             "and every 8 frames one point (BCD) is used."),
    0x0377: ("SHIELDDRAW", "Draw the shield: from the screen centre, one path of vectors through the 12 SHIELDPTS points, a lattice of diamonds across the screen (as in a captured frame); each segment's brightness comes from SHLD_SEED, scrambled every segment, so the shield flickers."),
    0x03CD: ("SHIELDPTS", "Shield path: 12 points, x and y bytes x 4 = screen positions, $FF ends."),
    0x03E6: ("SHIELDSND", "Shield up: shield sound on, bounce sound off."),
    0x0402: ("FTRCLOSE", "In a game, a fighter in play that comes nearer than z = $200 and is not yet flying away starts to (FTRn_AWAY = $4D), with the bounce sound."),
    0x045E: ("JOYSTICK", "Read the stick into the crosshair position XHAIR_X / XHAIR_Y: each axis is found by "
             "successive approximation (READAXIS) against the X register. A board jumper on input 14 selects "
             "a digital stick (inputs 1-4), handled at JOYDIGITAL."),
    0x0495: ("READAXIS", "Find the stick position on the axis OUT_MUX selects: halve the step each time, moving "
             "the X register toward the stick by JMI's comparison, 10 steps from $400 down to 2. Returns the position in AXIS_POS."),
    0x04D7: ("JOYDIGITAL", "Digital stick: inputs 1-4 move the crosshair by a fixed step, clamped to the screen."),
    0x051D: ("CLAMPXH", ""),
    0x0551: ("CROSSHAIR", "Position the crosshair, read the fire button and start a laser shot (SHOT) on a "
             "new press when the previous shot is over."),
    0x0586: ("FIGHTER1", "Fighter 1 (page 3): count down its explosion, then update and draw it through FTRUPDATE "
             "(return address in RET0)."),
    0x05B6: ("XHAIRDRAW", "In a game, draw the crosshair at XH_DRAW_X / XH_DRAW_Y from shape table XHAIRSHP: x,y pairs ($80 = 0) are lines from the last point, $FF x y moves, $FF $FF ends."),
    0x0617: ("XHAIRSHP", "Crosshair shape: x,y byte pairs ($80 = 0); $FF lifts the pen, $FF $FF ends."),
    0x0648: ("LASERS", "Lasers. While a shot is on (SHOT counts 9 down to 1) the laser sound plays and two "
             "beams come from the bottom corners toward the crosshair: each frame a beam's front is at (16 - "
             "SHOT) / 16 of the way, so the beams close in and shorten (as captured frames show). Here the "
             "left beam's front is worked out and the beam taken there; FIGHTER2 runs, then LASERL draws it. "
             "Input 8 (not wired) low would pulse the sound for the first frames."),
    0x0693: ("FIGHTER2", "Fighter 2 (page 4): as FIGHTER1."),
    0x06D4: ("LASERL", "Draw the left beam (with a shot on): a thin closed bolt of four segments from its front "
             "(TMP0A / TMP0B), out toward the half-way point to the crosshair and back. Input 13 (not wired) low "
             "would draw it as one vector instead (that path never ran in the traces)."),
    0x0724: ("BOLT", "The bolt: TMP07 / TMP08 = half the way from the front to the crosshair, TMP0E = a quarter "
             "of that across; the four points are visited through BEAMSEG, TMP0C naming the next step and TMP01 "
             "where to go when the bolt is done."),
    0x0749: ("BEAMSEG", "Draw one bolt segment from TMP02 / TMP03 to TMP04 / TMP09, then go where TMP0C says "
             "(BEAMNEXT)."),
    0x0780: ("BEAMNEXT", ""),
    0x0781: ("BOLTSTEP1", "Bolt point 2: a quarter of the way."),
    0x078F: ("BOLTSTEP2", "Bolt point 3: half way, offset the other side."),
    0x079C: ("BOLTSTEP3", "Bolt point 4: back to the front; then TMP01's step."),
    0x07A4: ("BEAMDONE", "After the left bolt: the right beam's front, (16 - SHOT) / 16 of the way from the "
             "bottom-right corner ($400) to the crosshair, and the beam taken there; FIGHTER3 runs, then LASERR "
             "draws it."),
    0x07BD: ("FIGHTER3", "Fighter 3 (page 5): as FIGHTER1."),
    0x07ED: ("LASERR", "Draw the right beam: the same bolt as LASERL (BOLT), from the right beam's front."),
    0x0855: ("AFTERFTR", "After the fighters: count the shot down; in a game the explosion sound plays while any "
             "fighter's FTRn_STATE is 3-7 (the first frames of its explosion), else it is turned off; then on "
             "to bank 1."),
    0x086F: ("NOSHIELD", "Shield down: shield and bounce sounds off; on to the stick."),
    0x08B6: ("ENDPASS", "After the stars. With the credit screen up (CREDIT_FLAG) straight on to bank 1; with "
             "a fighter in play, MOVEFTR and the rest of the pass; with none: in a game the next wave or the "
             "hyperspace jump (L02DE); in attract the title sequence (L02B6), started here when it is not "
             "running (TITLE_STATE = 1, TITLE_Z = $F00, TITLE_ANGLE = $10)."),
    0x08FB: ("TOBANK1", "T4K to bank 1: DRAWFTRS, returning to DRAWHUD (RET0 = $600, in bank 1)."),
    0x0904: ("READDIPS", "Read the three shield-points switches into SHLD_START (0-7)."),
    0x091C: ("SHIELDTAB", "Shield points for DIP settings 0-7, BCD: 15 20 30 40 50 60 70 80."),
    0x0924: ("DEVJUNK0", "Not Tailgunner data: 8080/Z80 machine code (CALL $xxxx = CD xx xx, JMP = C3 ...) and "
             "the text 'NEXT  PC', left in the EPROM by the development system. Nothing reads it."),
    0x0C00: ("FTRUPDATE", "Update one flying fighter. OBJ_PTR walks its record (from FTRn_X). Steering: the "
             "offset to the destination (FTRn_DESTX/Y) / 16, clamped to -$1E..$1E, is the angle to head for, "
             "turned round ($40 - it) once the fighter is nearer than its destination depth; each heading "
             "(FTRn_HEADX/Y) moves one step toward it. Motion: dx = speed sin(hx) cos(hy), dy = speed sin(hy), "
             "and z goes down by speed cos(hx) cos(hy) (9-step MUL chains on the SINCOS0 values). Then the "
             "projection (PROJDIV / PROJECT, depth z / 2) gives FTRn_SCRX/Y, and HITTEST. Returns through RET0."),
    0x0D93: ("PROJDIV", "Perspective: the reciprocal $200 / depth (depth in TMP09). The whole part by repeated "
             "subtraction into TMP04, then 11 shift-and-subtract steps for the fraction, left in TMP09."),
    0x0E0B: ("PROJECT", "Screen position: x and y (TMP05 / TMP06) times the reciprocal - the fraction with MUL "
             "steps into TMP07 / TMP08, then the whole part (TMP04) by adding the coordinate that many times."),
    0x0E6A: ("HITTEST", "Hit test, only in a shot's last three frames (SHOT 1-3, when the beams reach the "
             "crosshair) and only for a fighter farther than z = $200: a hit if its screen offset is within "
             "$16 + (-z >> 7) of the crosshair (XHAIR_X / XHAIR_Y) in x and in y, a target that grows as the "
             "fighter comes nearer."),
    0x0EAC: ("SCOREADD", "Score a hit: the fighter starts exploding, HIT_POINTS are added to the BCD score "
             "(units into SCORE_LO, the rest into SCORE_HI with its digits adjusted), and the hit flash starts. The third hit of a wave (HITS = 3) is scored twice."),
    0x0EE7: ("FTRRET", ""),
    0x0EEB: ("SINCOS0", "Sine of the angle in TMP1E (0-$7F a full turn, cut to 7 bits here) into TMP1A and its "
             "cosine into TMP1B, both x 255 and signed, from the quarter-wave table SINTAB0 by quadrant "
             "(below $20 the cosine is SINTAB0[$20 - angle]). Returns through RET1. (Bank 1 has its own "
             "copy, SINCOS1.)"),
    0x0F4C: ("SINTAB0", "Quarter sine wave, 33 bytes, $00-$FF."),
    0x0F6D: ("DEVJUNK1", "Not Tailgunner data: development-system leftovers (8080 code), not read."),
    # ------------------------------------------------------------ bank 1
    0x1000: ("TESTMODE", "Test pattern, reached at power-on with START held: turns every sound off, then each frame draws the figure TESTFIG (crossed lines, a square and a triangle; a capture is in README.md) for adjusting the monitor. Only a reset leaves it."),
    0x1005: ("TESTLOOP", "Test pattern loop: wait for the frame, clear the watchdog, centre the beam and draw TESTFIG with DRAWMODEL3D, which returns here."),
    0x1031: ("TESTFIG", "Test pattern figure: vertex list (x, y, z bytes, $FF end) and edge list at $105F, the format of MODELS."),
    0x1072: ("NEXTOBJ", ""),
    0x1080: ("DRAWFTRS", "Bank 1 entry of the frame: draw each live fighter's 3D model (DRAWMODEL), then return "
             "through RET0 to bank 1's HUD (DRAWHUD) or the title."),
    0x10B7: ("DRAWMODEL", "Draw one fighter. OBJ_PTR = its FTRn_SCRX: nothing is drawn if the centre is off the "
             "screen; else the model (FTRn_MODEL: edge-list pointer, then vertices) at FTRn_X/Y/Z, turned by two "
             "angles, FTRn_HEADX (sine / cosine into TMP1C / TMP1D) and FTRn_HEADY (TMP1A / TMP1B), and drawn by "
             "DRAWMODEL3D with OBJ_PTR = FTRn_STATE: dim while flying, bright while exploding. Returns through "
             "RET2."),
    0x1128: ("DRAWMODEL3D", "Rotate, project and draw one model: vertex list TMP16, edge list TMP17, position "
             "OBJ_X/Y/Z, angles as sine / cosine pairs TMP1C / TMP1D and TMP1A / TMP1B. Each vertex (bytes - $80, "
             "x 4) is rotated, moved to the position, projected (PROJDIV) and kept in the vertex buffer $E0-$FF "
             "as an edge first needs it; DRAWEDGES draws the edges between them. With OBJ_PTR (the fighter's "
             "FTRn_STATE) 2 or more - an explosion - each edge keeps its length but starts at centre + (start - "
             "centre) x state / 8: the pieces bunched at first (state 3), spreading out as the count rises to $18. The title letters use OBJ_PTR = 0. Returns through RET2."),
    0x139C: ("DRAWEDGES", ""),
    0x1479: ("MODELRET", ""),
    0x147D: ("DRAWFTRSRET", ""),
    0x1481: ("MODELS", "Fighter models: each a vertex list (x, y, z bytes, $80 = 0, $FF end) followed by an edge "
             "list (one byte per edge, the two vertex numbers in its nibbles, $FF end)."),
    0x1575: ("SINCOS1", "Bank 1 copy of SINCOS0 (table SINTAB1). Returns through RET1."),
    0x15D6: ("SINTAB1", "Quarter sine wave, 33 bytes, $00-$FF (same as SINTAB0)."),
    0x1600: ("DRAWHUD", "Score lines: 'SCORE' and 'HIGH SCORE' with their values, the shield points and the count of "
             "fighters that got past; then the coin and credit logic and the attract / start state."),
    0x1634: ("TXT_SCORE", "'SCORE' (ASCII, $FF ends)."),
    0x163A: ("HUDSCORE", "The player's score: brightened by the hit flash (HIT_FLASH), SCORE_HI / SCORE_LO printed under SCORE."),
    0x168F: ("FORMATION", "Every few frames the next formation step: the three fighters' positions come from the "
             "formation table at FORM_PTR."),
    0x1704: ("COINS", "Coins: read the coin latch, reset it, and add a credit (or half of one, with the 2 coins / "
             "1 credit switch)."),
    0x1735: ("HUDGAME", ""),
    0x17B9: ("GAMEOVER", "Game over: keep a new high score, end the shot and the sounds, show the title."),
    0x1804: ("TXT_HISCORE", "'HIGH SCORE' (ASCII, $5B is the space, $FF ends)."),
    0x180F: ("HUDHISCORE", "The high score: HISCORE_HI / HISCORE_LO printed under HIGH SCORE."),
    0x184B: ("HUDCREDITS", ""),
    0x1870: ("TXT_CREDITS", "'CREDITS' (ASCII, $FF ends)."),
    0x1878: ("SHOWCREDITS", "Credits on the attract screen (at most 9 shown), every sound off, PUSH START blinking (BLINK)."),
    0x1918: ("TXT_PUSHSTART", "'PUSH START' (ASCII, $5B is the space, $FF ends)."),
    0x1923: ("WAITSTART", "With a credit: wait for START; start a game (credits - 1, score and fighters cleared, "
             "shields from the DIP setting, 10 fighters to stop)."),
    0x195C: ("ATTRACT", "Attract mode: the title sequence (TITLE_STATE) - the 3D 'TAIL GUNNER' letters fly in and turn."),
    0x199D: ("TITLESTEP", "Title sequence, after SINCOS1: beam to the title position, then TITLE3D."),
    0x19C3: ("TOMAIN", "Back to MAINLOOP in bank 0 (T4K with P=1)."),
    0x19C7: ("TITLE3D", "Draw the 3D title letters (DRAWMODEL3D with the letter models at LETTERS)."),
    0x1A1B: ("LETTERS", "3D letter models for the title, same format as MODELS."),
    0x1AF3: ("PRINT", "Print a string or a BCD number with the vector font, characters 24 apart ($18). TMP03 / "
             "TMP04 = x, y of the first; TMP0E = a beam-settle delay before drawing. TMP0F = 0: the ASCII string "
             "at bank 1 address TMP05 + 1, ended by $FF. Otherwise TMP0F = 3 and TMP02 = digits + 1: BCD digits "
             "from the RAM word at TMP05, three per 12-bit word, high digit first, going on to the next word; "
             "leading zeros print as spaces, the last digit always prints. Returns through RET0."),
    0x1B6B: ("PRINTRET", ""),
    0x1B6E: ("PRINTCHR", "Draw one character: CHRINDEX gives its stroke list in CHRSTROKES, each stroke byte two "
             "nibbles naming points of the CHRGRID grid."),
    0x1BD2: ("CHRGRID", "Character grid: x,y byte pairs of the 15 points strokes join."),
    0x1BF0: ("CHRSTROKES", "Character strokes: bytes of two point numbers, $FF ends a character."),
    0x1C59: ("CHRINDEX", "Character index: offset into CHRSTROKES for each character code from '0' ($30)."),
    0x1C7E: ("FORMTAB", "Formation patterns: 8 pointers (low byte, then the high nibble), NEWWAVE picks one with RANDOM_LO & 7."),
    0x1C8E: ("FORMDATA", "Formation steps, 10 bytes each: x, y, z for fighters 1-3 (signed bytes, shifted left 4 into FTRn_DESTX/Y/Z) and the frames to the next step; $FF there ends the pattern."),
    0x1D70: ("TESTSNDOFF", "Test mode: every sound off, then on to the test pattern loop at $1005."),
    0x1DC0: ("NEWWAVE", "Start a wave: clear the three fighters, take the next pseudo-random value (RANDOM_LO / RANDOM_HI), "
             "and from it the formation, the fighters' starting positions and speeds and the points per hit "
             "(HIT_POINTS). Returns to MOVEFTR through RET1."),
    0x1FC8: ("DEVJUNK2", "Not Tailgunner data: development-system leftovers, not read."),
}

RAM = {
    # pages 0 and 1: scratch. Each routine uses these words in its own way; the
    # routine headers give their parameters, call sites note each one set, and
    # tailgunner_defines.asm lists the routines that touch every word.
    0x00: ("RET0", "return address for FTRUPDATE, PRINT and DRAWFTRS (also the RAM-clear pointer at RESET)"),
    0x01: ("TMP01", "PRINT: $FF, the end-of-string marker; lasers: address of the last beam step (BEAMDONE)"),
    0x02: ("TMP02", "PRINT: digits to print + 1; lasers: beam start x"),
    0x03: ("TMP03", "PRINT: x; DRAWMODEL3D: 2 x the vertex being projected (odd once all are)"),
    0x04: ("TMP04", "PRINT: y; projection: the quotient's integer part"),
    0x05: ("TMP05", "PRINT: string address (bank 1) or RAM address of the BCD number; DRAWEDGES: edge start x"),
    0x06: ("TMP06", "PRINT: character spacing ($18); DRAWEDGES: edge start y"),
    0x07: ("TMP07", "PRINT: the character; projection: screen x; DRAWEDGES: edge dx"),
    0x08: ("TMP08", "PRINT: stroke start x; projection: screen y; DRAWEDGES: edge dy"),
    0x09: ("TMP09", "PRINT: stroke start y; PROJDIV: depth, then the reciprocal"),
    0x0A: ("TMP0A", "lasers: beam end x; PRINT: stroke dx; DRAWEDGES: first vertex"),
    0x0B: ("TMP0B", "lasers: beam end y; PRINT: stroke dy; DRAWEDGES: the edge byte"),
    0x0C: ("TMP0C", "lasers: address of the next beam step (BEAMNEXT); PRINT: stroke point"),
    0x0D: ("TMP0D", "PROJDIV: remainder; PRINT: the stroke byte"),
    0x0E: ("TMP0E", "PRINT: beam-settle delay, then 'a non-zero digit printed'; DRAWEDGES: vertex x pointer"),
    0x0F: ("TMP0F", "PRINT: 0 = string, else the digit within the BCD word (3, 2, 1); DRAWEDGES: vertex y pointer"),
    0x10: ("OBJ_X", "position of the thing being drawn: x (crosshair, shield centre, fighter, model)"),
    0x11: ("OBJ_Y", "position of the thing being drawn: y"),
    0x12: ("OBJ_Z", "position of the thing being drawn: z (depth)"),
    0x13: ("TMP13", "XHAIRDRAW / SHIELDDRAW: beam x; FTRUPDATE: velocity x; models: rotated x"),
    0x14: ("TMP14", "XHAIRDRAW / SHIELDDRAW: beam y; FTRUPDATE: velocity y; models: rotated y"),
    0x15: ("TMP15", "FTRUPDATE: speed; models: rotated z"),
    0x16: ("TMP16", "XHAIRDRAW / SHIELDDRAW: table pointer; FTRUPDATE: steering x; DRAWMODEL3D: vertex list"),
    0x17: ("TMP17", "FTRUPDATE: steering y; DRAWMODEL3D: edge list (bank 1)"),
    0x18: ("CONST_FF", "the constant $FF (end-of-list marker), compared with each table byte"),
    0x19: ("OBJ_PTR", "pointer into the fighter record being worked on; 0 while the title letters are drawn"),
    0x1A: ("TMP1A", "SINCOS result: sine of TMP1E; models: sine of the second angle"),
    0x1B: ("TMP1B", "SINCOS result: cosine of TMP1E; models: cosine of the second angle"),
    0x1C: ("TMP1C", "models: sine of the first angle (bank); XHAIRDRAW: line end x"),
    0x1D: ("TMP1D", "models: cosine of the first angle; XHAIRDRAW: line end y"),
    0x1E: ("TMP1E", "SINCOS input: angle, 0-$7F a full turn ($20 = 90 degrees)"),
    0x1F: ("RET1", "return address for SINCOS0/1 and NEWWAVE"),    # page 2: stick, crosshair, formation, random
    0x20: ("FORM_TIMER", "frames to the next formation step"),
    0x22: ("RANDOM_LO", "pseudo-random generator, low word (seeded $2D3 at power-on)"),
    0x23: ("RANDOM_HI", "pseudo-random generator, high word (seeded $2D3 at power-on)"),
    0x24: ("HIT_POINTS", "points for a hit this wave, BCD: 7, 11, 17 or 23 (NEWWAVE picks one from RANDOM_HI)"),
    0x25: ("FORM_PTR", "formation table pointer (bank 1 offset)"),
    0x26: ("CTR_X", "DRAWMODEL: projected centre x"),
    0x27: ("CTR_Y", "DRAWMODEL: projected centre y"),
    0x28: ("AXIS_POS", "READAXIS in / out: the stick position on the selected axis; changed only by 7 or more"),
    0x29: ("HITS", "fighters hit this wave; on the third, SCOREADD adds the points twice (seen: 0-4, never left at 3)"),
    0x2A: ("STICK_X", "stick x as last read"),
    0x2B: ("STICK_Y", "stick y as last read"),
    0x2C: ("XHAIR_X", "crosshair x, -$17C..$1A4 from the centre"),
    0x2D: ("XHAIR_Y", "crosshair y, -$12C..$12C from the centre (also READAXIS's return address while it runs)"),
    0x2E: ("TMP2E", "READAXIS: the step; NEWWAVE: the new wave's speed, then the FORMTAB entry"),
    0x2F: ("RET2", "return address for DRAWMODEL / DRAWMODEL3D; READAXIS's working estimate of the stick"),
    # pages 3-5: the three fighters (same layout, +$10 / +$20)
    0x30: ("FTR1_MODEL", "fighter 1: model address in bank 1, 0 = not in play"),
    0x31: ("FTR1_X", "fighter 1: x"),
    0x32: ("FTR1_Y", "fighter 1: y"),
    0x33: ("FTR1_Z", "fighter 1: z (distance; it has got past when this passes the limit)"),
    0x34: ("FTR1_HEADX", "fighter 1: heading angle in x, -$20..$20 ($80 = a turn), turned one step a frame toward the steering angle; also the model's turn in DRAWMODEL"),
    0x35: ("FTR1_HEADY", "fighter 1: heading angle in y, as FTR1_HEADX"),
    0x36: ("FTR1_SPEED", "fighter 1: speed along its heading (0 once it flies away)"),
    0x37: ("FTR1_STATE", "fighter 1: 0 flying; a hit sets 3, then +1 a frame to $18, when PASSCHK removes it (seen: 0, 3-$18)"),
    0x38: ("FTR1_DESTX", "fighter 1: destination x (formation step)"),
    0x39: ("FTR1_DESTY", "fighter 1: destination y"),
    0x3A: ("FTR1_DESTZ", "fighter 1: destination z"),
    0x3D: ("FTR1_AWAY", "fighter 1: fly-away speed once it is close ($4D), added to z each frame until it leaves"),
    0x3F: ("FTR1_FORM", "fighter 1: formation table index"),
    0x40: ("FTR2_MODEL", "fighter 2: as FTR1_MODEL"),
    0x41: ("FTR2_X", "fighter 2: x"),
    0x42: ("FTR2_Y", "fighter 2: y"),
    0x43: ("FTR2_Z", "fighter 2: z"),
    0x44: ("FTR2_HEADX", "fighter 2: heading angle in x, -$20..$20 ($80 = a turn), turned one step a frame toward the steering angle; also the model's turn in DRAWMODEL"),
    0x45: ("FTR2_HEADY", "fighter 2: heading angle in y, as FTR2_HEADX"),
    0x46: ("FTR2_SPEED", "fighter 2: speed along its heading (0 once it flies away)"),
    0x47: ("FTR2_STATE", "fighter 2: as FTR1_STATE"),
    0x48: ("FTR2_DESTX", "fighter 2: destination x (formation step)"),
    0x49: ("FTR2_DESTY", "fighter 2: destination y"),
    0x4A: ("FTR2_DESTZ", "fighter 2: destination z"),
    0x4D: ("FTR2_AWAY", "fighter 2: fly-away speed once it is close ($4D), added to z each frame until it leaves"),
    0x4F: ("FTR2_FORM", "fighter 2: formation table index"),
    0x50: ("FTR3_MODEL", "fighter 3: as FTR1_MODEL"),
    0x51: ("FTR3_X", "fighter 3: x"),
    0x52: ("FTR3_Y", "fighter 3: y"),
    0x53: ("FTR3_Z", "fighter 3: z"),
    0x54: ("FTR3_HEADX", "fighter 3: heading angle in x, -$20..$20 ($80 = a turn), turned one step a frame toward the steering angle; also the model's turn in DRAWMODEL"),
    0x55: ("FTR3_HEADY", "fighter 3: heading angle in y, as FTR3_HEADX"),
    0x56: ("FTR3_SPEED", "fighter 3: speed along its heading (0 once it flies away)"),
    0x57: ("FTR3_STATE", "fighter 3: as FTR1_STATE"),
    0x58: ("FTR3_DESTX", "fighter 3: destination x (formation step)"),
    0x59: ("FTR3_DESTY", "fighter 3: destination y"),
    0x5A: ("FTR3_DESTZ", "fighter 3: destination z"),
    0x5D: ("FTR3_AWAY", "fighter 3: fly-away speed once it is close ($4D), added to z each frame until it leaves"),
    0x5F: ("FTR3_FORM", "fighter 3: formation table index"),
    # page 6: player
    0x60: ("FIRE_WAIT", "frames until the fire button can start another shot"),
    0x61: ("FIRE_LAST", "fire button as read last frame (a shot needs a new press)"),
    0x62: ("SHOT", "laser shot timer: 9 when fired, counts down; 0 = no shot"),
    0x63: ("XH_DRAW_X", "crosshair x as drawn"),
    0x64: ("XH_DRAW_Y", "crosshair y as drawn"),
    0x69: ("FTRS_LEFT", "fighters that may still get past: 10 at the start of a game, which ends at 0; 0 in attract. "
           "The HUD shows 10 minus this"),
    0x6A: ("SCORE_HI", "score: thousands, hundreds and tens, 3 BCD digits (338 is SCORE_HI $033, SCORE_LO $008 in a RAM snapshot; past 9999 the top digit goes on to $A-$F)"),
    0x6B: ("SCORE_LO", "score: units digit, 0-9"),
    0x6C: ("HISCORE_HI", "high score: thousands, hundreds and tens (as SCORE_HI)"),
    0x6D: ("HISCORE_LO", "high score: units digit"),
    0x6F: ("FIRE_NOW", "fire button this frame / score carry"),
    # page 7
    0x70: ("STAR_T", "star brightness band"),
    0x71: ("HIT_FLASH", "frames of the hit flash"),
    0x72: ("PASS_FLASH", "frames of the flash when a fighter gets past"),
    0x73: ("WAVE_TIMER", "hyperspace between waves: counts 1 to $24 (WAVEDELAY); above 4 the stars streak, at 5 the hyperspace sound starts; a fighter getting past also steps it"),
    0x78: ("COIN_SEEN", "coin latch as read this frame"),
    0x79: ("HALF_CREDIT", "first of two coins with the 2 coins / 1 credit switch"),
    0x7A: ("CREDIT_FLAG", "COINS: the credits being counted (then 0); set to 1 while the credit / PUSH START screen is up (HUDCREDITS), when ENDPASS leaves the fighters alone"),
    0x7B: ("BLINK", "frame counter for blinking text"),
    0x7C: ("TITLE_ANGLE", "attract: title letters' angle"),
    0x7D: ("TITLE_STATE", "attract: title sequence state"),
    0x7E: ("TITLE_Z", "attract: title letters' distance"),
    # page 8: shields and coins
    0x80: ("SHLD_FRAMES", "frames the shield has been held (a point goes every 8)"),
    0x81: ("SHLD_POINTS", "shield points, BCD"),
    0x82: ("SHLD_START", "shield points a game starts with, BCD (from SHIELDTAB by the DIP setting)"),
    0x83: ("SHLD_SEED", "shield flicker: scrambled for every shield segment, its bit 0 picks bright or dim (seeded $2D3 at power-on)"),
    0x89: ("CREDITS", "credits (a RAM snapshot shows 0, 1, 2 as coins drop, 1 after START)"),
    0x8A: ("GAMES", "games started"),
    0x8B: ("SHLD_BLINK", "blink counter for low shields"),
    0x8C: ("CREDITS_SHOWN", "credits as printed, at most 9"),
    # stars and projection buffer
    0x3B: ("FTR1_SCRX", "fighter 1: screen x of its centre + $200, from FTRUPDATE, for DRAWMODEL (off screen at $400 and up)"),
    0x3C: ("FTR1_SCRY", "fighter 1: screen y of its centre + $180 (off screen at $300 and up)"),
    0x4B: ("FTR2_SCRX", "fighter 2: as FTR1_SCRX"),
    0x4C: ("FTR2_SCRY", "fighter 2: as FTR1_SCRY"),
    0x5B: ("FTR3_SCRX", "fighter 3: as FTR1_SCRX"),
    0x5C: ("FTR3_SCRY", "fighter 3: as FTR1_SCRY"),
    0x65: ("LASER_DX", "lasers: x offset of the beam end, SHOT x the crosshair distance (MUL)"),
    0x66: ("LASER_DY", "lasers: y offset of the beam end"),
    0x74: ("STAR_BOOST", "hyperspace: the star's step / 4, added WAVE_TIMER times more, so stars rush inward faster"),
    0x75: ("IN15_PLUS1", "input 15 + 1 (attract); input 15 is not connected on Tailgunner and reads 1"),
    0xC3: ("STAR_RND", "new star: the random number from ROM, folded to -$7F..$7F"),
    0xC5: ("STAR_DX", "the star being moved: its x step, (distance from the centre) / 32"),
    0xC6: ("STAR_DY", "the star being moved: its y step"),
    0xC7: ("STAR_SLOT", "new star: offset into STARPOS (0-$3E, steps of 2)"),
    0xC8: ("STAR_ADX", "abs(STAR_DX): sets the star's brightness band and when it is restarted"),
    0xC9: ("STAR_ADY", "abs(STAR_DY)"),
    0xC0: ("STAR_SEED", "ROM address walked as the random source for new stars"),
    0xC1: ("STAR_PX", "pointer to the star's x word"),
    0xC2: ("STAR_PY", "pointer to the star's y word"),
}
UNUSED = [0x21, 0x3E, 0x4E, 0x5E, 0x67, 0x68, 0x6E, 0x76, 0x77, 0x7F, 0xC4] + list(range(0x84, 0x89)) \
    + list(range(0x8D, 0xA0)) + list(range(0xCA, 0xE0))
for r in UNUSED:
    RAM[r] = ("RAM_%02X" % r, "not used: only the power-on RAM clear writes it, nothing reads it")
for i in range(16):
    RAM[0xA0 + 2 * i] = ("STAR%d_X" % i, "star %d: x" % i)
    RAM[0xA1 + 2 * i] = ("STAR%d_Y" % i, "star %d: y" % i)
for i in range(16):
    RAM[0xE0 + 2 * i] = ("VTX%d_X" % i, "vertex buffer: screen x of vertex %d of the model being drawn" % i)
    RAM[0xE1 + 2 * i] = ("VTX%d_Y" % i, "vertex buffer: screen y of vertex %d" % i)

# Routine parameters: at each call, the store to one of these words before the
# jump is noted with its meaning.
CALL_PARAMS = {
    0x1AF3: {0x00: "PRINT: return address", 0x02: "PRINT: digits to print + 1", 0x03: "PRINT: x",
             0x04: "PRINT: y", 0x05: "PRINT: what to print (string in bank 1 / RAM word)",
             0x0E: "PRINT: beam-settle delay", 0x0F: "PRINT: 0 = string, 3 = BCD number"},
    0x0C00: {0x00: "FTRUPDATE: return address", 0x19: "FTRUPDATE: the fighter (address of FTRn_X)"},
    0x10B7: {0x19: "DRAWMODEL: the fighter (address of FTRn_SCRX)", 0x2F: "DRAWMODEL: return address"},
    0x1128: {0x16: "DRAWMODEL3D: vertex list", 0x17: "DRAWMODEL3D: edge list", 0x2F: "DRAWMODEL3D: return address",
             0x19: "DRAWMODEL3D: 0 = title letters", 0x10: "DRAWMODEL3D: x", 0x11: "DRAWMODEL3D: y",
             0x12: "DRAWMODEL3D: z", 0x1A: "DRAWMODEL3D: sine of angle 2", 0x1B: "DRAWMODEL3D: cosine of angle 2",
             0x1C: "DRAWMODEL3D: sine of angle 1", 0x1D: "DRAWMODEL3D: cosine of angle 1"},
    0x0EEB: {0x1E: "SINCOS0: angle", 0x1F: "SINCOS0: return address"},
    0x1575: {0x1E: "SINCOS1: angle", 0x1F: "SINCOS1: return address"},
    0x0495: {0x28: "READAXIS: starting position", 0x2D: "READAXIS: return address"},
    0x1DC0: {0x1F: "NEWWAVE: return address"},
    0x1080: {0x00: "DRAWFTRS: return address"},
}

# comment blocks printed above a RAM word in tailgunner_defines.asm
RAM_BLOCKS = {
    0xE0: [
        "Vertex buffer $E0-$FF: not drawn itself. DRAWMODEL3D projects a model's",
        "vertices one at a time and keeps each one's screen position here (x + $200,",
        "y + $180, at L1395 / L139B); DRAWEDGES reads two of them for every edge byte,",
        "skips the edge when an end is off screen (x >= $400 or y >= $300), else moves",
        "the beam to the first (IV) and draws to the second (DV). A vertex is projected",
        "only when an edge first needs it (L13AF), so projecting and drawing alternate.",
        "Every model drawn overwrites it; 4-bit vertex numbers allow 16 vertices.",
    ],
}

NOTES = {
    0x0001: "B = 0",
    0x0003: "A = $F01: the first address cleared is $01",
    0x000B: "RAM[I] = 0",
    0x0041: "A = START (0 = held)",
    0x005C: "beam to the centre: X = $200, Y = $180",
    0x006E: "wait for the frame timer",
    0x0071: "CST: clear the watchdog",
    0x0230: "two ROM bytes as random numbers",
    0x02E9: "start a new wave (returns to MOVEFTR)",
    0x1B11: "next character of the string",
}

BLOCKS = {
    0x0000: [
        " The CCPU idioms used throughout:",
        "  * a jump loads J with LPAI and then jumps (JMP, or a conditional one, which",
        "    leave J set for the next jump); T4K jumps to the bank the P register selects",
        "    (P=1: bank 0, P=2: bank 1).",
        "  * there is no stack: a caller stores its return address in RAM (LDAI hi /",
        "    A8I lo / STA RETx) and the routine returns with TST RETx / LPAP / JMP.",
        "  * a compare is an add or subtract of the constant: A4I n / Jcc compares the",
        "    previous accumulator with n.",
        "  * SSA (or any B-variant jump) makes the next instruction use the B accumulator.",
        "  * LDAI B,#$300 / SHRB / LDAI #$200 ... JVN / IV moves the beam (X from A,",
        "    Y from B); NV / ... / DV draws a vector to A,B.",
        "  * a sound is one OUT sequence: bit 0 of A to OUT_SND_DATA, bits 1-3 to the",
        "    address outputs, then two strobes.",
    ],
    0x0924: [" Bytes $0924-$0BFF are development-system leftovers, not part of the game."],
}


# line-level comments live in comments.py
import comments as _c
NOTES.update(_c.NOTES)
for _a, _b in _c.BLOCKS.items():
    BLOCKS.setdefault(_a, []).extend(_b)

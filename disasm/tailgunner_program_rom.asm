;Tailgunner (Cinematronics, 1979) - annotated disassembly of the program ROM $0000-$1FFF.
;MAME set 'tailg': tgunner.t70/.p70 (bank 0, $0000-$0FFF) and tgunner.t71/.p71
;(bank 1, $1000-$1FFF); the t chips hold the even bytes, the p chips the odd ones.
;The CPU is the Cinematronics CCPU, a TTL processor with 12-bit registers
;and 8-bit opcodes; see README.md for the instruction set and this syntax.
;No source code is known to survive. Code and data were separated by running
;the ROM (trace/tgtrace.exe, the AAE ccpu.cpp core) and following its jumps
;(analyze.py); every name and description was written for this disassembly.
;Every line below was re-encoded and byte-compared with the ROM (verify.py).
;Syntax: .alias, .byte, .org; $ = hex; # = immediate; B, = the instruction
;uses the B accumulator; P:$x = RAM word $x of the page the P register selects
;(the page is known statically wherever a full address or name is shown).

.org $0000

.include "tailgunner_defines.asm"


;==============================================================================
; BANK 0   $0000-$0FFF   tgunner.t70 (even bytes) + tgunner.p70 (odd bytes)
;==============================================================================

; The CCPU idioms used throughout:
;  * a jump loads J with LPAI and then jumps (JMP, or a conditional one, which
;    leave J set for the next jump); T4K jumps to the bank the P register selects
;    (P=1: bank 0, P=2: bank 1).
;  * there is no stack: a caller stores its return address in RAM (LDAI hi /
;    A8I lo / STA RETx) and the routine returns with TST RETx / LPAP / JMP.
;  * a compare is an add or subtract of the constant: A4I n / Jcc compares the
;    previous accumulator with n.
;  * SSA (or any B-variant jump) makes the next instruction use the B accumulator.
;  * LDAI B,#$300 / SHRB / LDAI #$200 ... JVN / IV moves the beam (X from A,
;    Y from B); NV / ... / DV draws a vector to A,B.
;  * a sound is one OUT sequence: bit 0 of A to OUT_SND_DATA, bits 1-3 to the
;    address outputs, then two strobes.

;------------------------------------------------------------------------------
; RESET - Power-on and watchdog reset entry. The CCPU starts here with every
;   register zero. Clears RAM $01-$FF, resets the coin latch, then reads the
;   shield DIP switches.
;------------------------------------------------------------------------------
RESET:
L0000:  SSA
L0001:  LDAI B,#$000                ;B = 0
L0002:  LDAI #$F00
L0003:  A8I  #$01                   ;A = $F01: the first address cleared is $01
L0005:  LPAI CLRRAM
L0007:  SETP $0                     ;page 0 for the clear loop
CLRRAM:
L0008:  STA  RET0
L0009:  WS   RET0                   ;I = the address in RET0
L000A:  SSA
L000B:  STAP B                      ;RAM[I] = 0  store to [RET0]
L000C:  A4I  #$1
L000D:  JCZ                         ;until A + 1 carries (reaches $1000) -> CLRRAM
L000E:  STA  RET0                   ;RET0 = 0 again
L000F:  LDAI #$000
L0010:  A4I  #$1
L0011:  OUT  OUT_COIN_RESET         ;latch input low (a later high clears the coin)
L0012:  LPAI READDIPS
L0014:  JMP

L0015:  .byte $F5, $79, $CD, $8F, $06, $F1, $C9, $FE  ;$0015-$0025, not read in the traces
L001D:  .byte $20, $C8, $FE, $09, $C8, $FE, $2C, $C8
L0025:  .byte $FE
; The shield points the DIP switches select: READDIPS left the setting (0-7) in
; SHLD_START; LKP reads SHIELDTAB+setting and STAP puts the BCD value back there.

;------------------------------------------------------------------------------
; INIT2 - Power-on, part 2: shield points from the DIP setting, random seeds,
;   player state cleared; START held at power-on branches to the test pattern
;   (TESTMODE).
;------------------------------------------------------------------------------
INIT2:
L0026:  LDAI #$900                  ;A = $91C + the switch setting (I is still SHLD_START)
L0027:  A8I  #$1C
L0029:  ADDP
L002A:  LKP                         ;table read $091C-$0923
L002C:  STAP                        ;SHLD_START = the shield points, BCD
L002D:  LDAI #$200
L002E:  A8I  #$D3                   ;$2D3: the seed
L0030:  SETP $8
L0031:  STA  SHLD_SEED
L0032:  SETP $2
L0033:  STA  RANDOM_LO
L0034:  STA  RANDOM_HI
L0035:  LDAI #$000
L0036:  STA  XHAIR_X                ;crosshair at the centre
L0037:  STA  XHAIR_Y
L0038:  LDAI #$000
L0039:  SETP $6
L003A:  STA  SHOT
L003B:  STA  FIRE_WAIT
L003C:  STA  SCORE_HI
L003D:  STA  HISCORE_HI
L003E:  STA  FTRS_LEFT              ;no game: attract
L003F:  A4I  #$1
L0040:  STA  FIRE_LAST              ;fire 'released' last frame
; START held at power-on: the test pattern instead of the game.
L0041:  INP  IN_START               ;A = START (0 = held)  input 7: start button (active low)
L0042:  A4I  #$1
L0043:  LPAI MAINLOOP
L0045:  JEQ                         ;if IN_START = 1 (not pressed) -> MAINLOOP
TESTMODE_GO:
L0046:  LPAI TESTMODE               ;T4K to bank 1
L0048:  SETP $2
L0049:  T4K


;------------------------------------------------------------------------------
; WAVEDELAY - Between waves: WAVE_TIMER counts up to $24 frames (the hyperspace
;   sound starts at 5), then goes to 0 so the next pass starts a new wave.
;------------------------------------------------------------------------------
WAVEDELAY:
L004A:  A8I  #$1F
L004C:  TST  WAVE_TIMER
L004D:  LPAI L0056
L004F:  JCZ                         ;if A < WAVE_TIMER -> L0056
L0050:  LDAP                        ;WAVE_TIMER
L0051:  A4I  #$1
L0052:  STAP                        ;store to WAVE_TIMER
L0053:  LPAI MAINLOOP
L0055:  JMP

L0056:  LDAI #$000
L0057:  STAP

;------------------------------------------------------------------------------
; MAINLOOP - Top of the frame: the beam to the centre, then FRM waits for the
;   frame timer. One pass, in order: SNDOFF (attract) / PASSCHK, STARS, ENDPASS
;   (waves, title), MOVEFTR, SHIELDS, FTRCLOSE, JOYSTICK, CROSSHAIR (fire),
;   FIGHTER1, XHAIRDRAW, LASERS, FIGHTER2, LASERL, FIGHTER3, LASERR, AFTERFTR;
;   then bank 1: DRAWFTRS, DRAWHUD (score, shields, coins), the attract / start
;   screens, and back here.
;------------------------------------------------------------------------------
MAINLOOP:
L0058:  NOP                         ;runs with A and with B
L0059:  NOP
; Every frame starts with the beam at the centre ($200, $180), a short delay,
; and FRM: the CPU stops until the frame timer restarts it (38 Hz in the AAE driver).
L005A:  SSA
L005B:  LDAI B,#$300
L005C:  SHRB                        ;beam to the centre: X = $200, Y = $180
L005D:  LDAI #$200
L005E:  LPAI L0060
L0060:  JVN                         ;while the vector generator is busy -> L0060
L0061:  IV
L0062:  LDAI #$000
L0063:  S8I  #$12
L0065:  A4I  #$1
L0066:  LPAI L0065
L0068:  JCZ                         ;count up to 0 (a delay of $12 loops) -> L0065
L0069:  LDAI #$000
L006A:  A4I  #$B
L006B:  SSA
L006C:  LDAI B,#$000
L006D:  NV                          ;normalise A = $00B, B = 0 before the frame wait
WAITFRM:
L006E:  FRM                         ;wait for the frame timer
L006F:  FRM                         ;repeated FRM: fetched and skipped, no second wait
L0070:  A4I  #$1                    ;A + 1, then CST adds [I] and clears the watchdog
L0071:  CST                         ;CST: clear the watchdog
; In attract (FTRS_LEFT = 0) all sounds are turned off each frame.
L0072:  LDAI #$000
L0073:  SETP $6
L0074:  TST  FTRS_LEFT
L0075:  LPAI PASSCHK
L0077:  JCZ                         ;if FTRS_LEFT > 0 -> PASSCHK

;------------------------------------------------------------------------------
; SNDOFF - In attract (FTRS_LEFT = 0) every sound is turned off.
;------------------------------------------------------------------------------
SNDOFF:
L0078:  LDAI #$000
L0079:  A8I  #$1E
L007B:  OUT  OUT_SND_DATA           ;sound: explosion off
L007C:  SHR
L007D:  OUT  OUT_SND_A0
L007E:  SHR
L007F:  OUT  OUT_SND_A1
L0080:  SHR
L0081:  OUT  OUT_SND_A2
L0082:  SHR
L0083:  OUT  OUT_SND_STROBE
L0084:  SHR
L0085:  OUT  OUT_SND_STROBE
L0086:  LDAI #$000
L0087:  A8I  #$1A
L0089:  OUT  OUT_SND_DATA           ;sound: laser off
L008A:  SHR
L008B:  OUT  OUT_SND_A0
L008C:  SHR
L008D:  OUT  OUT_SND_A1
L008E:  SHR
L008F:  OUT  OUT_SND_A2
L0090:  SHR
L0091:  OUT  OUT_SND_STROBE
L0092:  SHR
L0093:  OUT  OUT_SND_STROBE
L0094:  LDAI #$000
L0095:  A8I  #$18
L0097:  OUT  OUT_SND_DATA           ;sound: shield off
L0098:  SHR
L0099:  OUT  OUT_SND_A0
L009A:  SHR
L009B:  OUT  OUT_SND_A1
L009C:  SHR
L009D:  OUT  OUT_SND_A2
L009E:  SHR
L009F:  OUT  OUT_SND_STROBE
L00A0:  SHR
L00A1:  OUT  OUT_SND_STROBE
L00A2:  LDAI #$000
L00A3:  A8I  #$16
L00A5:  OUT  OUT_SND_DATA           ;sound: bounce off
L00A6:  SHR
L00A7:  OUT  OUT_SND_A0
L00A8:  SHR
L00A9:  OUT  OUT_SND_A1
L00AA:  SHR
L00AB:  OUT  OUT_SND_A2
L00AC:  SHR
L00AD:  OUT  OUT_SND_STROBE
L00AE:  SHR
L00AF:  OUT  OUT_SND_STROBE
L00B0:  LDAI #$000
L00B1:  A8I  #$14
L00B3:  OUT  OUT_SND_DATA           ;sound: hyperspace off
L00B4:  SHR
L00B5:  OUT  OUT_SND_A0
L00B6:  SHR
L00B7:  OUT  OUT_SND_A1
L00B8:  SHR
L00B9:  OUT  OUT_SND_A2
L00BA:  SHR
L00BB:  OUT  OUT_SND_STROBE
L00BC:  SHR
L00BD:  OUT  OUT_SND_STROBE
; Fighter 1 (the same code follows for fighters 2 and 3):
;  * explosion finished (FTRn_STATE above $17): remove it;
;  * else, in play and nearer than z = $115: it got past - in a game one fewer
;    left, the pass flash, and one more count of hyperspace; then remove it.

;------------------------------------------------------------------------------
; PASSCHK - Per fighter: an explosion that has run its course (FTRn_STATE past
;   $17) is removed; a fighter in play nearer than z = $115 has got past and is
;   removed - with a game on FTRS_LEFT goes down by one, the pass flash starts
;   and WAVE_TIMER (hyperspace) is stepped.
;------------------------------------------------------------------------------
PASSCHK:
L00BE:  LDAI #$000
L00BF:  A8I  #$17
L00C1:  SETP $3
L00C2:  TST  FTR1_STATE
L00C3:  LPAI L00DF
L00C5:  JCZ                         ;explosion over  if $17 < FTR1_STATE -> L00DF
L00C6:  LDAI #$100
L00C7:  A8I  #$15
L00C9:  TST  FTR1_Z
L00CA:  LPAI L00E2
L00CC:  JCZ                         ;still far away  if $115 < FTR1_Z -> L00E2
L00CD:  LDAI #$000
L00CE:  TST  FTR1_MODEL
L00CF:  JEQ                         ;if FTR1_MODEL = 0 -> L00E2
L00D0:  SETP $6
L00D1:  LDA  FTRS_LEFT
L00D2:  LPAI L00DF
L00D4:  JEQ                         ;attract: just remove it  if FTRS_LEFT = 0 -> L00DF
L00D5:  S4I  #$1                    ;a fighter got past
L00D6:  STAP                        ;store to FTRS_LEFT
L00D7:  LDAI #$000
L00D8:  A4I  #$F                    ;15 frames of flash
L00D9:  SETP $7
L00DA:  STA  PASS_FLASH
L00DB:  SETP $7
L00DC:  LDA  WAVE_TIMER
L00DD:  A4I  #$1                    ;starts (or extends) the hyperspace jump
L00DE:  STAP                        ;store to WAVE_TIMER
L00DF:  LDAI #$000                  ;remove the fighter
L00E0:  SETP $3
L00E1:  STA  FTR1_MODEL
L00E2:  LDAI #$000
L00E3:  A8I  #$17
L00E5:  SETP $4
L00E6:  TST  FTR2_STATE
L00E7:  LPAI L0103
L00E9:  JCZ                         ;if $17 < FTR2_STATE -> L0103
L00EA:  LDAI #$100
L00EB:  A8I  #$15
L00ED:  TST  FTR2_Z
L00EE:  LPAI L0106
L00F0:  JCZ                         ;if $115 < FTR2_Z -> L0106
L00F1:  LDAI #$000
L00F2:  TST  FTR2_MODEL
L00F3:  JEQ                         ;if FTR2_MODEL = 0 -> L0106
L00F4:  SETP $6
L00F5:  LDA  FTRS_LEFT
L00F6:  LPAI L0103
L00F8:  JEQ                         ;if FTRS_LEFT = 0 -> L0103
L00F9:  S4I  #$1
L00FA:  STAP                        ;store to FTRS_LEFT
L00FB:  LDAI #$000
L00FC:  A4I  #$F
L00FD:  SETP $7
L00FE:  STA  PASS_FLASH
L00FF:  SETP $7
L0100:  LDA  WAVE_TIMER
L0101:  A4I  #$1
L0102:  STAP                        ;store to WAVE_TIMER
L0103:  LDAI #$000
L0104:  SETP $4
L0105:  STA  FTR2_MODEL
L0106:  LDAI #$000
L0107:  A8I  #$17
L0109:  SETP $5
L010A:  TST  FTR3_STATE
L010B:  LPAI L0127
L010D:  JCZ                         ;if $17 < FTR3_STATE -> L0127
L010E:  LDAI #$100
L010F:  A8I  #$15
L0111:  TST  FTR3_Z
L0112:  LPAI L012A
L0114:  JCZ                         ;if $115 < FTR3_Z -> L012A
L0115:  LDAI #$000
L0116:  TST  FTR3_MODEL
L0117:  JEQ                         ;if FTR3_MODEL = 0 -> L012A
L0118:  SETP $6
L0119:  LDA  FTRS_LEFT
L011A:  LPAI L0127
L011C:  JEQ                         ;if FTRS_LEFT = 0 -> L0127
L011D:  S4I  #$1
L011E:  STAP                        ;store to FTRS_LEFT
L011F:  LDAI #$000
L0120:  A4I  #$F
L0121:  SETP $7
L0122:  STA  PASS_FLASH
L0123:  SETP $7
L0124:  LDA  WAVE_TIMER
L0125:  A4I  #$1
L0126:  STAP                        ;store to WAVE_TIMER
L0127:  LDAI #$000
L0128:  SETP $5
L0129:  STA  FTR3_MODEL
; No hyperspace under way: make sure the hyperspace sound is off.
L012A:  SETP $7
L012B:  LDA  WAVE_TIMER
L012C:  LDAI #$000
L012D:  LPAI L013E
L012F:  JLT                         ;if 0 < WAVE_TIMER -> L013E
L0130:  LDAI #$000
L0131:  A8I  #$14
L0133:  OUT  OUT_SND_DATA           ;sound: hyperspace off
L0134:  SHR
L0135:  OUT  OUT_SND_A0
L0136:  SHR
L0137:  OUT  OUT_SND_A1
L0138:  SHR
L0139:  OUT  OUT_SND_A2
L013A:  SHR
L013B:  OUT  OUT_SND_STROBE
L013C:  SHR
L013D:  OUT  OUT_SND_STROBE
L013E:  LPAI L0140
L0140:  JVN                         ;while the vector generator is busy -> L0140
L0141:  LDAI #$000
L0142:  OUT  OUT_INTENSITY          ;dim

;------------------------------------------------------------------------------
; STARS - Star field, 16 stars ($A0-$BF, x and y). Star coordinates are twice
;   the screen's, the centre at ($408, $308). Each frame every star moves 1/32
;   of its distance toward the centre (the view is backward, from the tail, so
;   stars run in from the edges; checked on two captured frames: all 16 move
;   inward). In hyperspace (WAVE_TIMER 4 and up) the step is multiplied up and
;   the stars are bright. A star is a dot whose brightness comes from its
;   distance band (STARBRT); one that reaches the centre or leaves the range
;   restarts at the next STARPOS point plus a random offset.
;------------------------------------------------------------------------------
STARS:
L0143:  LDAI #$000
L0144:  A8I  #$A0
L0146:  SETP $C
L0147:  STA  STAR_PX
STARLP:
L0148:  LDA  STAR_PX
L0149:  A4I  #$1
L014A:  STA  STAR_PY
L014B:  LDAI #$400
L014C:  A4I  #$8
L014D:  WS   STAR_PX                ;I = the address in STAR_PX
L014E:  SUBP                        ;$408 - x: distance from the centre (star coordinates are doubled)  [STAR_PX]
L014F:  ASR
L0150:  ASR
L0151:  ASR
L0152:  ASR
L0153:  ASR                         ;/ 32: the step toward the centre
L0154:  STA  STAR_DX
L0155:  SSA
L0156:  LDAI B,#$300
L0157:  SHRB
L0158:  LDAI #$200                  ;beam to the centre first
L0159:  LPAI L015B
L015B:  JVN                         ;while the vector generator is busy -> L015B
L015C:  IV
L015D:  LDAI #$800
L015E:  LDA  STAR_DX
L015F:  LPAI L0164
L0161:  JLT                         ;if STAR_DX < $800 -> L0164
L0162:  LDAI #$000
L0163:  SUBP                        ;STAR_DX
L0164:  STA  STAR_ADX               ;abs(step)
L0165:  SHR
L0166:  SHR
L0167:  SETP $7
L0168:  STA  STAR_T                 ;|dx| / 4: the start of the brightness band
L0169:  LDAI #$000
L016A:  A4I  #$4
L016B:  SETP $7
L016C:  TST  WAVE_TIMER
L016D:  LPAI L018B
L016F:  JLT                         ;if WAVE_TIMER < 4 -> L018B
L0170:  SSA                         ;hyperspace: B = -WAVE_TIMER
L0171:  LDAI B,#$000
L0172:  SSA
L0173:  SUBP B                      ;WAVE_TIMER
L0174:  SHRB
L0175:  SSA
L0176:  S4I  B,#$1
L0177:  SETP $C
L0178:  LDA  STAR_DX
L0179:  A4I  #$2
L017A:  ASR
L017B:  ASR
L017C:  SETP $7
L017D:  STA  STAR_BOOST             ;step / 4
L017E:  LDAI #$000
L017F:  LPAI L0181
L0181:  ADDP
L0182:  SSA
L0183:  A4I  B,#$1
L0184:  JCZ                         ;A = STAR_BOOST x WAVE_TIMER  until B + 1 carries (reaches $1000) -> L0181
L0185:  SETP $C
L0186:  ADD  STAR_DX
L0187:  STAP                        ;the step grows with the hyperspace count  store to STAR_DX
L0188:  LDAI #$000
L0189:  A4I  #$1
L018A:  OUT  OUT_INTENSITY          ;stars are bright in hyperspace  bright
L018B:  SETP $C
L018C:  LDA  STAR_DX
L018D:  WS   STAR_PX                ;I = the address in STAR_PX
L018E:  ADDP                        ;[STAR_PX]
L018F:  STAP                        ;x moves toward the centre  store to [STAR_PX]
L0190:  LDAI #$300
L0191:  A4I  #$8
L0192:  WS   STAR_PY                ;I = the address in STAR_PY
L0193:  SUBP                        ;[STAR_PY]
L0194:  ASR
L0195:  ASR
L0196:  ASR
L0197:  ASR
L0198:  ASR
L0199:  STA  STAR_DY
L019A:  LDAI #$800
L019B:  LDAP                        ;STAR_DY
L019C:  LPAI L01A1
L019E:  JLT                         ;if STAR_DY < $800 -> L01A1
L019F:  LDAI #$000
L01A0:  SUBP                        ;STAR_DY
L01A1:  STA  STAR_ADY
L01A2:  SHR
L01A3:  SHR
L01A4:  SETP $7
L01A5:  ADD  STAR_T
L01A6:  STAP                        ;+ |dy| / 4: the brightness band  store to STAR_T
L01A7:  LDAI #$000
L01A8:  A4I  #$4
L01A9:  SETP $7
L01AA:  TST  WAVE_TIMER
L01AB:  LPAI L01C6
L01AD:  JLT                         ;if WAVE_TIMER < 4 -> L01C6
L01AE:  SSA
L01AF:  LDAI B,#$000
L01B0:  SSA
L01B1:  SUBP B                      ;WAVE_TIMER
L01B2:  SHRB
L01B3:  SSA
L01B4:  S4I  B,#$1
L01B5:  SETP $C
L01B6:  LDA  STAR_DY
L01B7:  A4I  #$2
L01B8:  ASR
L01B9:  ASR
L01BA:  SETP $7
L01BB:  STA  STAR_BOOST
L01BC:  LDAI #$000
L01BD:  LPAI L01BF
L01BF:  ADDP
L01C0:  SSA
L01C1:  A4I  B,#$1
L01C2:  JCZ                         ;until B + 1 carries (reaches $1000) -> L01BF
L01C3:  SETP $C
L01C4:  ADD  STAR_DY
L01C5:  STAP                        ;store to STAR_DY
L01C6:  SETP $C
L01C7:  LDA  STAR_DY
L01C8:  WS   STAR_PY                ;I = the address in STAR_PY
L01C9:  ADDP                        ;[STAR_PY]
L01CA:  STAP                        ;y moves toward the centre  store to [STAR_PY]
; Restart the star if it is off the range or near the centre.
L01CB:  LDAI #$900
L01CC:  WS   STAR_PX                ;I = the address in STAR_PX
L01CD:  SUBP                        ;[STAR_PX]
L01CE:  LPAI NEWSTAR
L01D0:  JCZ                         ;x out of range  if $900 < [STAR_PX] -> NEWSTAR
L01D1:  LDAI #$700
L01D2:  WS   STAR_PY                ;I = the address in STAR_PY
L01D3:  SUBP                        ;[STAR_PY]
L01D4:  JCZ                         ;y out of range  if $700 < [STAR_PY] -> NEWSTAR
L01D5:  LDA  STAR_ADX
L01D6:  S4I  #$4
L01D7:  LPAI L01DF
L01D9:  JLT                         ;if 4 < STAR_ADX -> L01DF
L01DA:  LDA  STAR_ADY
L01DB:  S4I  #$5
L01DC:  LPAI NEWSTAR
L01DE:  JCZ                         ;at the centre: restart it  if STAR_ADY < 5 -> NEWSTAR
; Draw the star: beam to it, wait, then a dot with the band's brightness.
L01DF:  WS   STAR_PY                ;I = the address in STAR_PY
L01E0:  SSA
L01E1:  LDAP B                      ;[STAR_PY]
L01E2:  SHRB
L01E3:  WS   STAR_PX                ;I = the address in STAR_PX
L01E4:  LDAP                        ;[STAR_PX]
L01E5:  ASR                         ;screen coordinates are half the star's
L01E6:  IV                          ;beam to the star
L01E7:  LDAI #$000
L01E8:  S8I  #$4E
L01EA:  A4I  #$1
L01EB:  LPAI L01EA
L01ED:  JCZ                         ;count up to 0 (a delay of $4E loops) -> L01EA
L01EE:  LDAI #$200
L01EF:  A8I  #$66
L01F1:  SETP $7
L01F2:  ADD  STAR_T
L01F3:  LKP                         ;the dot's brightness for its band  table read $0267-$0274
L01F5:  SHL
L01F6:  SSA
L01F7:  LDAI B,#$000
L01F8:  NV                          ;normalise: the band's shift becomes the dot's beam time
L01F9:  SETP $C
L01FA:  WS   STAR_PY                ;I = the address in STAR_PY
L01FB:  SSA
L01FC:  LDAP B                      ;[STAR_PY]
L01FD:  SHRB
L01FE:  WS   STAR_PX                ;I = the address in STAR_PX
L01FF:  LDAP                        ;[STAR_PX]
L0200:  ASR
L0201:  DV                          ;a zero-length vector: a dot
L0202:  LDA  STAR_PX
L0203:  A4I  #$2
L0204:  STAP                        ;store to STAR_PX
L0205:  LDAI #$000                  ;next star
L0206:  A8I  #$C0
L0208:  LDAP                        ;STAR_PX
L0209:  LPAI STARLP
L020B:  JLT                         ;all 16 done  if STAR_PX < $C0 -> STARLP
L020C:  LPAI ENDPASS                ;on to the end of the pass checks
L020E:  JMP

; New star: the next restart point from STARPOS (x and y, signed, x 8), plus
; random offsets. The random numbers are ROM bytes: STAR_SEED walks through
; the program and two bytes at a time, folded to -$7F..$7F, are added.

;------------------------------------------------------------------------------
; NEWSTAR - Restart a star out at the next STARPOS point (STAR_SLOT); the
;   offset comes from ROM bytes read at the walking pointer STAR_SEED.
;------------------------------------------------------------------------------
NEWSTAR:
L020F:  LDAI #$000
L0210:  A8I  #$3F
L0212:  TST  STAR_SLOT
L0213:  ANDP                        ;STAR_SLOT
L0214:  A4I  #$2                    ;the next of the 32 restart points
L0215:  STAP                        ;store to STAR_SLOT
L0216:  LDAI #$200
L0217:  A8I  #$74
L0219:  ADD  STAR_SLOT
L021A:  STA  STAR_DX
L021B:  A4I  #$1
L021C:  LKP                         ;table read $0277-$02B5
L021E:  S8I  #$80
L0220:  SHL
L0221:  SHL
L0222:  SHL
L0223:  STA  STAR_DY                ;y offset x 8
L0224:  LDA  STAR_DX
L0225:  LKP                         ;table read $0276-$02B4
L0227:  S8I  #$80
L0229:  SHL
L022A:  SHL
L022B:  SHL
L022C:  STAP                        ;x offset x 8  store to STAR_DX
L022D:  LDA  STAR_SEED
L022E:  A4I  #$1
L022F:  STAP                        ;STAR_SEED + 1: the next ROM address  store to STAR_SEED
L0230:  LKP                         ;two ROM bytes as random numbers  reads bytes all over the ROM (random numbers)
L0232:  ADDP                        ;STAR_SEED
L0233:  LKP                         ;reads bytes all over the ROM (random numbers)
L0235:  ADDP                        ;STAR_SEED
L0236:  STA  STAR_RND               ;A = ROM[ROM[p] + p] + p, with p = STAR_SEED
L0237:  LDAI #$000
L0238:  A8I  #$7F
L023A:  ANDP                        ;STAR_RND
L023B:  STAP                        ;store to STAR_RND
L023C:  SHR
L023D:  LPAI L0243                  ;a random sign
L023F:  JOS                         ;if the bit shifted out of A was 1 -> L0243
L0240:  LDAI #$000
L0241:  SUBP                        ;STAR_RND
L0242:  STAP                        ;store to STAR_RND
L0243:  LDAI #$400
L0244:  ADDP
L0245:  ADD  STAR_DX
L0246:  WS   STAR_PX                ;I = the address in STAR_PX
L0247:  STAP                        ;x = $400 + random + the restart point  store to [STAR_PX]
L0248:  LDA  STAR_SEED
L0249:  A4I  #$1
L024A:  STAP                        ;store to STAR_SEED
L024B:  LKP                         ;reads bytes all over the ROM (random numbers)
L024D:  ADDP                        ;STAR_SEED
L024E:  LKP                         ;reads bytes all over the ROM (random numbers)
L0250:  ADDP                        ;STAR_SEED
L0251:  STA  STAR_RND
L0252:  LDAI #$000
L0253:  A8I  #$7F
L0255:  ANDP                        ;STAR_RND
L0256:  STAP                        ;store to STAR_RND
L0257:  SHR
L0258:  LPAI L025E
L025A:  JOS                         ;if the bit shifted out of A was 1 -> L025E
L025B:  LDAI #$000
L025C:  SUBP                        ;STAR_RND
L025D:  STAP                        ;store to STAR_RND
L025E:  LDAI #$300
L025F:  ADDP
L0260:  ADD  STAR_DY
L0261:  WS   STAR_PY                ;I = the address in STAR_PY
L0262:  STAP                        ;y = $300 + random + the restart point  store to [STAR_PY]
L0263:  LPAI L014B
L0265:  JMP

L0266:  .byte $01                   ;$0266-$02B5, read by LKP at L01F3, L021C, L0225
STARBRT:
L0267:  .byte $01, $02, $04, $08, $10, $20, $40, $60
L026F:  .byte $70, $80, $90, $A0, $B0, $B0, $B0
STARPOS:
L0276:  .byte $BE, $DC, $04, $AE, $61, $24, $61, $DC
L027E:  .byte $FC, $97, $80, $24, $80, $DC, $04, $80
L0286:  .byte $FC, $DC, $BE, $24, $23, $24, $23, $DC
L028E:  .byte $FC, $80, $9F, $24, $DD, $DC, $04, $52
L0296:  .byte $42, $DC, $DD, $24, $04, $3B, $FC, $52
L029E:  .byte $04, $DC, $42, $24, $9F, $DC, $FC, $69
L02A6:  .byte $04, $97, $FC, $AE, $04, $69, $FC, $C5
L02AE:  .byte $04, $24, $FC, $24, $04, $C5, $FC, $3B
; Attract, title sequence (TITLE_STATE counts up): states 2-7 would play the
; explosion sound if input 15 were low; it is not connected, so they are
; silent. The sequence ends at $1F.
L02B6:  LDAP
L02B7:  S8I  #$1F                   ;title sequence over at $1F
L02B9:  LPAI L02DC
L02BB:  JLT                         ;if $1F < A -> L02DC
L02BC:  LDAI #$000
L02BD:  A4I  #$2
L02BE:  TST  TITLE_STATE
L02BF:  LPAI L08ED
L02C1:  JLT                         ;if TITLE_STATE < 2 -> L08ED
L02C2:  A4I  #$5
L02C3:  TST  TITLE_STATE
L02C4:  JCZ                         ;if 7 < TITLE_STATE -> L08ED
L02C5:  INP  $F                     ;input 15 is not connected: it reads 1  input 15: not wired on Tailgunner (reads 1)
L02C6:  A4I  #$1
L02C7:  SETP $7
L02C8:  STA  IN15_PLUS1
L02C9:  LDAI #$000
L02CA:  A4I  #$1
L02CB:  ANDP                        ;IN15_PLUS1
L02CC:  A8I  #$1E                   ;explosion sound on only if input 15 is low
L02CE:  OUT  OUT_SND_DATA           ;sound: explosion on or off (bit 0 of A)
L02CF:  SHR
L02D0:  OUT  OUT_SND_A0
L02D1:  SHR
L02D2:  OUT  OUT_SND_A1
L02D3:  SHR
L02D4:  OUT  OUT_SND_A2
L02D5:  SHR
L02D6:  OUT  OUT_SND_STROBE
L02D7:  SHR
L02D8:  OUT  OUT_SND_STROBE
L02D9:  LPAI TOBANK1
L02DB:  JMP

L02DC:  LDAI #$000
L02DD:  STAP                        ;the title sequence is over
; No fighters left in play during a game. WAVE_TIMER = 0 (all three were shot)
; starts the next wave at once; otherwise some got past and the hyperspace
; jump runs first: no shot, the hyperspace sound up to count 5, the stars
; rushing in (STARS), and the next wave when WAVEDELAY wraps the count to 0.
L02DE:  LDAI #$000
L02DF:  SETP $7
L02E0:  TST  WAVE_TIMER
L02E1:  LPAI L02ED
L02E3:  JCZ                         ;if WAVE_TIMER > 0 -> L02ED
L02E4:  LDAI #$300
L02E5:  A8I  #$08
L02E7:  SETP $1
L02E8:  STA  RET1                   ;NEWWAVE: return address
L02E9:  LPAI NEWWAVE                ;start a new wave (returns to MOVEFTR)  T4K to bank 1
L02EB:  SETP $2
L02EC:  T4K

L02ED:  LDAI #$000
L02EE:  SETP $6
L02EF:  STA  SHOT                   ;no shot during hyperspace
L02F0:  STA  FIRE_WAIT
L02F1:  A4I  #$5
L02F2:  SETP $7
L02F3:  TST  WAVE_TIMER
L02F4:  LPAI WAVEDELAY
L02F6:  JCZ                         ;if 5 < WAVE_TIMER -> WAVEDELAY
L02F7:  LDAI #$000
L02F8:  A8I  #$15
L02FA:  OUT  OUT_SND_DATA           ;sound: hyperspace on
L02FB:  SHR
L02FC:  OUT  OUT_SND_A0
L02FD:  SHR
L02FE:  OUT  OUT_SND_A1
L02FF:  SHR
L0300:  OUT  OUT_SND_A2
L0301:  SHR
L0302:  OUT  OUT_SND_STROBE
L0303:  SHR
L0304:  OUT  OUT_SND_STROBE
L0305:  LDAI #$000
L0306:  A4I  #$5
L0307:  JMP                         ;J is still WAVEDELAY

; A fighter flying away (FTRn_AWAY set, not exploding) moves out by its
; fly-away speed until z reaches $F00, and is removed there.

;------------------------------------------------------------------------------
; MOVEFTR - Fighter motion: each live fighter (page 3, 4, 5) moves by its speed
;   until its position passes the limit, when it is cleared.
;   Reached by the jump through RAM at L1FC7.
;------------------------------------------------------------------------------
MOVEFTR:
L0308:  NOP                         ;runs with A and with B
L0309:  LDAI #$000
L030A:  SETP $3
L030B:  TST  FTR1_STATE
L030C:  LPAI L0319
L030E:  JCZ                         ;if FTR1_STATE > 0 -> L0319
L030F:  LDA  FTR1_AWAY
L0310:  JEQ                         ;not flying away  if FTR1_AWAY = 0 -> L0319
L0311:  ADD  FTR1_Z
L0312:  STAP                        ;z += the fly-away speed  store to FTR1_Z
L0313:  LDAI #$F00
L0314:  TST  FTR1_Z
L0315:  JLT                         ;not gone yet  if FTR1_Z < $F00 -> L0319
L0316:  LDAI #$000
L0317:  STA  FTR1_MODEL             ;gone: remove it
L0318:  STA  FTR1_AWAY
L0319:  LDAI #$000
L031A:  SETP $4
L031B:  TST  FTR2_STATE
L031C:  LPAI L0329
L031E:  JCZ                         ;if FTR2_STATE > 0 -> L0329
L031F:  LDA  FTR2_AWAY
L0320:  JEQ                         ;if FTR2_AWAY = 0 -> L0329
L0321:  ADD  FTR2_Z
L0322:  STAP                        ;store to FTR2_Z
L0323:  LDAI #$F00
L0324:  TST  FTR2_Z
L0325:  JLT                         ;if FTR2_Z < $F00 -> L0329
L0326:  LDAI #$000
L0327:  STA  FTR2_MODEL
L0328:  STA  FTR2_AWAY
L0329:  LDAI #$000
L032A:  SETP $5
L032B:  TST  FTR3_STATE
L032C:  LPAI SHIELDS
L032E:  JCZ                         ;if FTR3_STATE > 0 -> SHIELDS
L032F:  LDA  FTR3_AWAY
L0330:  JEQ                         ;if FTR3_AWAY = 0 -> SHIELDS
L0331:  ADD  FTR3_Z
L0332:  STAP                        ;store to FTR3_Z
L0333:  LDAI #$F00
L0334:  TST  FTR3_Z
L0335:  JLT                         ;if FTR3_Z < $F00 -> SHIELDS
L0336:  LDAI #$000
L0337:  STA  FTR3_MODEL
L0338:  STA  FTR3_AWAY
; The shield: in a game, with the button held and points left. Every 8th frame
; one point goes (BCD), and the shield ring is drawn every frame it is up.

;------------------------------------------------------------------------------
; SHIELDS - Shields: while the shield button is held and shield points remain,
;   the shield is drawn and every 8 frames one point (BCD) is used.
;------------------------------------------------------------------------------
SHIELDS:
L0339:  LDAI #$000
L033A:  SETP $6
L033B:  TST  FTRS_LEFT
L033C:  LPAI NOSHIELD
L033E:  JEQ                         ;if FTRS_LEFT = 0 -> NOSHIELD
L033F:  INP  IN_SHIELD              ;input 6: shield button (active low)
L0340:  A4I  #$1
L0341:  LPAI NOSHIELD
L0343:  JEQ                         ;the button is not held  if IN_SHIELD = 1 (not pressed) -> NOSHIELD
L0344:  LDAI #$000
L0345:  SETP $8
L0346:  TST  SHLD_POINTS
L0347:  JEQ                         ;if SHLD_POINTS = 0 -> NOSHIELD
L0348:  LDA  SHLD_FRAMES
L0349:  A4I  #$1
L034A:  STAP                        ;store to SHLD_FRAMES
L034B:  S4I  #$8
L034C:  LPAI SHIELDDRAW
L034E:  JCZ                         ;not the 8th frame yet  if SHLD_FRAMES+1 < 8 -> SHIELDDRAW
L034F:  LDAI #$000
L0350:  STAP                        ;store to SHLD_FRAMES
L0351:  LDA  SHLD_POINTS            ;BCD decrement of a 3-digit word:
L0352:  LDAI #$000
L0353:  LPAI L0373
L0355:  JEQ                         ;if SHLD_POINTS = 0 -> L0373
L0356:  A8I  #$FF
L0358:  ANDP                        ;SHLD_POINTS
L0359:  LDAI #$000
L035A:  LPAI L036D
L035C:  JEQ                         ;x00: subtract $67 ($100 -> $099)  if SHLD_POINTS & $FF = 0 -> L036D
L035D:  A4I  #$F
L035E:  ANDP                        ;SHLD_POINTS
L035F:  LDAI #$000
L0360:  LPAI L0368
L0362:  JEQ                         ;x0: subtract 7 ($20 -> $19)  if SHLD_POINTS & $F = 0 -> L0368
L0363:  LDAP                        ;SHLD_POINTS
L0364:  S4I  #$1                    ;else subtract 1
L0365:  LPAI L0376
L0367:  JMP

L0368:  LDAP
L0369:  S4I  #$7
L036A:  LPAI L0376
L036C:  JMP

;[static] not executed in the traces; reached by following the jumps
L036D:  LDAP
L036E:  S8I  #$67
L0370:  LPAI L0376
L0372:  JMP

L0373:  LDAI #$900                  ;0 -> $999
L0374:  A8I  #$99
L0376:  STAP                        ;SHLD_POINTS = the result
; The shield: one path of vectors from the screen centre through the 12
; SHIELDPTS points (a lattice of diamonds), each segment bright or dim by
; the scrambled SHLD_SEED, so it flickers.

;------------------------------------------------------------------------------
; SHIELDDRAW - Draw the shield: from the screen centre, one path of vectors
;   through the 12 SHIELDPTS points, a lattice of diamonds across the screen
;   (as in a captured frame); each segment's brightness comes from SHLD_SEED,
;   scrambled every segment, so the shield flickers.
;------------------------------------------------------------------------------
SHIELDDRAW:
L0377:  SSA
L0378:  LDAI B,#$300
L0379:  SHRB
L037A:  SETP $1
L037B:  SSA
L037C:  STA  B,OBJ_Y
L037D:  LDAI #$200
L037E:  STA  OBJ_X                  ;the path starts at the screen centre
L037F:  LPAI L0381
L0381:  JVN                         ;while the vector generator is busy -> L0381
L0382:  IV
L0383:  LDAI #$000
L0384:  S8I  #$43
L0386:  A4I  #$1
L0387:  LPAI L0386
L0389:  JCZ                         ;count up to 0 (a delay of $43 loops) -> L0386
L038A:  LDAI #$300
L038B:  A8I  #$CB
L038D:  STA  TMP16                  ;SHIELDPTS - 2
L038E:  LDAI #$000
L038F:  A8I  #$FF
L0391:  STA  CONST_FF
L0392:  LDA  OBJ_X
L0393:  SSA
L0394:  LDA  B,OBJ_Y
L0395:  IV
L0396:  LDA  TMP16
L0397:  A4I  #$2
L0398:  STAP                        ;store to TMP16
L0399:  LKP                         ;table read $03CD-$03E5
L039B:  TST  CONST_FF
L039C:  LPAI SHIELDSND
L039E:  JEQ                         ;if A = CONST_FF -> SHIELDSND
L039F:  SHL                         ;x 4: the point's screen x
L03A0:  SHL
L03A1:  SUB  OBJ_X
L03A2:  STA  TMP13                  ;dx to the next point
L03A3:  LDA  TMP16
L03A4:  A4I  #$1
L03A5:  LKP                         ;table read $03CE-$03E4
L03A7:  SHL
L03A8:  SHL
L03A9:  SUB  OBJ_Y
L03AA:  STA  TMP14                  ;dy to the next point
L03AB:  LDA  TMP13
L03AC:  SSA
L03AD:  LDA  B,TMP14
L03AE:  NV
L03AF:  ADD  OBJ_X
L03B0:  SSA
L03B1:  ADD  B,OBJ_Y
L03B2:  DV                          ;the segment
L03B3:  LDA  TMP13
L03B4:  ADD  OBJ_X
L03B5:  STAP                        ;store to OBJ_X
L03B6:  LDA  TMP14
L03B7:  ADD  OBJ_Y
L03B8:  STAP                        ;the segment's end is the next start  store to OBJ_Y
L03B9:  SETP $8
L03BA:  TST  SHLD_SEED
L03BB:  LPAI L03BD
L03BD:  LDAI #$000
L03BE:  SSA
L03BF:  LDAP B                      ;scramble SHLD_SEED: B = seed / 4,
L03C0:  SHRB
L03C1:  SHRB
L03C2:  ADDP                        ;A = seed + seed / 4, x 2, + seed, / 2
L03C3:  SHL
L03C4:  ADDP
L03C5:  SHR
L03C6:  STAP
L03C7:  OUT  OUT_INTENSITY          ;its bit 0: this segment bright or dim  vector intensity: A bit 0 = 1 bright, 0 dim
L03C8:  JVN                         ;while the vector generator is busy -> L03BD
L03C9:  SETP $1
L03CA:  LPAI L0392
L03CC:  JMP

;$03CD-$03E5, read by LKP at L0399, L03A5
SHIELDPTS:
L03CD:  .byte $C0, $A0              ;point  0: screen x $300  y $280
L03CF:  .byte $E0, $80              ;point  1: screen x $380  y $200
L03D1:  .byte $80, $20              ;point  2: screen x $200  y $080
L03D3:  .byte $20, $80              ;point  3: screen x $080  y $200
L03D5:  .byte $40, $A0              ;point  4: screen x $100  y $280
L03D7:  .byte $80, $60              ;point  5: screen x $200  y $180
L03D9:  .byte $C0, $20              ;point  6: screen x $300  y $080
L03DB:  .byte $E0, $40              ;point  7: screen x $380  y $100
L03DD:  .byte $80, $A0              ;point  8: screen x $200  y $280
L03DF:  .byte $20, $40              ;point  9: screen x $080  y $100
L03E1:  .byte $40, $20              ;point 10: screen x $100  y $080
L03E3:  .byte $80, $60              ;point 11: screen x $200  y $180
L03E5:  .byte $FF                   ;end

;------------------------------------------------------------------------------
; SHIELDSND - Shield up: shield sound on, bounce sound off.
;------------------------------------------------------------------------------
SHIELDSND:
L03E6:  LDAI #$000
L03E7:  A8I  #$19
L03E9:  OUT  OUT_SND_DATA           ;sound: shield on
L03EA:  SHR
L03EB:  OUT  OUT_SND_A0
L03EC:  SHR
L03ED:  OUT  OUT_SND_A1
L03EE:  SHR
L03EF:  OUT  OUT_SND_A2
L03F0:  SHR
L03F1:  OUT  OUT_SND_STROBE
L03F2:  SHR
L03F3:  OUT  OUT_SND_STROBE
L03F4:  LDAI #$000
L03F5:  A8I  #$16
L03F7:  OUT  OUT_SND_DATA           ;sound: bounce off
L03F8:  SHR
L03F9:  OUT  OUT_SND_A0
L03FA:  SHR
L03FB:  OUT  OUT_SND_A1
L03FC:  SHR
L03FD:  OUT  OUT_SND_A2
L03FE:  SHR
L03FF:  OUT  OUT_SND_STROBE
L0400:  SHR
L0401:  OUT  OUT_SND_STROBE

;------------------------------------------------------------------------------
; FTRCLOSE - In a game, a fighter in play that comes nearer than z = $200 and
;   is not yet flying away starts to (FTRn_AWAY = $4D), with the bounce sound.
;------------------------------------------------------------------------------
FTRCLOSE:
L0402:  LDAI #$000
L0403:  SETP $6
L0404:  TST  FTRS_LEFT
L0405:  LPAI JOYSTICK
L0407:  JEQ                         ;if FTRS_LEFT = 0 -> JOYSTICK
L0408:  SETP $3
L0409:  TST  FTR1_MODEL
L040A:  LPAI L0424
L040C:  JEQ                         ;if FTR1_MODEL = 0 -> L0424
L040D:  TST  FTR1_AWAY
L040E:  JCZ                         ;already flying away  if FTR1_AWAY > 0 -> L0424
L040F:  LDAI #$200
L0410:  TST  FTR1_Z
L0411:  JCZ                         ;not close yet  if $200 < FTR1_Z -> L0424
L0412:  LDAI #$000
L0413:  A8I  #$4D                   ;fly away at $4D a frame
L0415:  STA  FTR1_AWAY
L0416:  LDAI #$000
L0417:  A8I  #$17
L0419:  OUT  OUT_SND_DATA           ;sound: bounce on
L041A:  SHR
L041B:  OUT  OUT_SND_A0
L041C:  SHR
L041D:  OUT  OUT_SND_A1
L041E:  SHR
L041F:  OUT  OUT_SND_A2
L0420:  SHR
L0421:  OUT  OUT_SND_STROBE
L0422:  SHR
L0423:  OUT  OUT_SND_STROBE
L0424:  LDAI #$000
L0425:  SETP $4
L0426:  TST  FTR2_MODEL
L0427:  LPAI L0441
L0429:  JEQ                         ;if FTR2_MODEL = 0 -> L0441
L042A:  TST  FTR2_AWAY
L042B:  JCZ                         ;if FTR2_AWAY > 0 -> L0441
L042C:  LDAI #$200
L042D:  TST  FTR2_Z
L042E:  JCZ                         ;if $200 < FTR2_Z -> L0441
L042F:  LDAI #$000
L0430:  A8I  #$4D
L0432:  STA  FTR2_AWAY
L0433:  LDAI #$000
L0434:  A8I  #$17
L0436:  OUT  OUT_SND_DATA           ;sound: bounce on
L0437:  SHR
L0438:  OUT  OUT_SND_A0
L0439:  SHR
L043A:  OUT  OUT_SND_A1
L043B:  SHR
L043C:  OUT  OUT_SND_A2
L043D:  SHR
L043E:  OUT  OUT_SND_STROBE
L043F:  SHR
L0440:  OUT  OUT_SND_STROBE
L0441:  LDAI #$000
L0442:  SETP $5
L0443:  TST  FTR3_MODEL
L0444:  LPAI JOYSTICK
L0446:  JEQ                         ;if FTR3_MODEL = 0 -> JOYSTICK
L0447:  TST  FTR3_AWAY
L0448:  JCZ                         ;if FTR3_AWAY > 0 -> JOYSTICK
L0449:  LDAI #$200
L044A:  TST  FTR3_Z
L044B:  JCZ                         ;if $200 < FTR3_Z -> JOYSTICK
L044C:  LDAI #$000
L044D:  A8I  #$4D
L044F:  STA  FTR3_AWAY
L0450:  LDAI #$000
L0451:  A8I  #$17
L0453:  OUT  OUT_SND_DATA           ;sound: bounce on
L0454:  SHR
L0455:  OUT  OUT_SND_A0
L0456:  SHR
L0457:  OUT  OUT_SND_A1
L0458:  SHR
L0459:  OUT  OUT_SND_A2
L045A:  SHR
L045B:  OUT  OUT_SND_STROBE
L045C:  SHR
L045D:  OUT  OUT_SND_STROBE

;------------------------------------------------------------------------------
; JOYSTICK - Read the stick into the crosshair position XHAIR_X / XHAIR_Y: each
;   axis is found by successive approximation (READAXIS) against the X
;   register. A board jumper on input 14 selects a digital stick (inputs 1-4),
;   handled at JOYDIGITAL.
;------------------------------------------------------------------------------
JOYSTICK:
L045E:  LDAI #$000
L045F:  SETP $6
L0460:  TST  FTRS_LEFT
L0461:  LPAI FIGHTER1
L0463:  JEQ                         ;if FTRS_LEFT = 0 -> FIGHTER1
L0464:  INP  $E                     ;input 14 low would select a digital stick  input 14: not wired on Tailgunner (reads 1)
L0465:  LDAI #$000
L0466:  LPAI JOYDIGITAL
L0468:  JEQ                         ;if input 14 = 0 -> JOYDIGITAL
; Analog stick: read x then y with READAXIS (return addresses in XHAIR_Y,
; which is then overwritten by the result).
L0469:  SETP $2
L046A:  LDAI #$000
L046B:  OUT  OUT_MUX                ;the stick's x axis
L046C:  LPAI L046E
L046E:  JVN                         ;while the vector generator is busy -> L046E
L046F:  LDA  STICK_X                ;start from the last reading
L0470:  STA  AXIS_POS               ;READAXIS: starting position
L0471:  LDAI #$400
L0472:  A8I  #$78
L0474:  STA  XHAIR_Y                ;READAXIS: return address  return address: L0478
L0475:  LPAI READAXIS
L0477:  JMP                         ;call; returns to L0478 via XHAIR_Y

L0478:  LDA  AXIS_POS
L0479:  STA  STICK_X                ;the reading
L047A:  LDAI #$800
L047B:  ADDP                        ;STICK_X
L047C:  ASR                         ;+ $800 (the middle becomes 0), / 4: the crosshair's x
L047D:  ASR
L047E:  STA  XHAIR_X
L047F:  LDAI #$000
L0480:  A4I  #$1
L0481:  OUT  OUT_MUX                ;the stick's y axis
L0482:  LDA  STICK_Y                ;the y axis the same way
L0483:  STA  AXIS_POS               ;READAXIS: starting position
L0484:  LDAI #$400
L0485:  A8I  #$8B
L0487:  STA  XHAIR_Y                ;READAXIS: return address
L0488:  LPAI READAXIS
L048A:  JMP                         ;call; returns to L048B

L048B:  LDA  AXIS_POS
L048C:  STA  STICK_Y
L048D:  LDAI #$800
L048E:  ADDP                        ;STICK_Y
L048F:  ASR
L0490:  ASR
L0491:  STA  XHAIR_Y                ;/ 4: the crosshair's y
L0492:  LPAI CLAMPXH
L0494:  JMP


;------------------------------------------------------------------------------
; READAXIS - Find the stick position on the axis OUT_MUX selects: halve the
;   step each time, moving the X register toward the stick by JMI's comparison,
;   10 steps from $400 down to 2. Returns the position in AXIS_POS.
;   Called from L0477, L048A (return address in XHAIR_Y).
;------------------------------------------------------------------------------
READAXIS:
L0495:  LDAI #$800
L0496:  SETP $2
L0497:  STA  RET2                   ;the estimate starts at $800 (the middle)
L0498:  SHR
L0499:  STA  TMP2E                  ;the first step: $400
L049A:  LPAI L049C
L049C:  JVN                         ;while the vector generator is busy -> L049C
L049D:  LDAI #$800
L049E:  ADD  RET2
L049F:  IV                          ;X = the estimate: the comparator tests the stick against it
L04A0:  LDAI #$000
L04A1:  SSA
L04A2:  LDAI B,#$100
L04A3:  NV                          ;normalise A = 0, B = $100
L04A4:  LDAI #$000
L04A5:  S8I  #$11
L04A7:  A4I  #$1
L04A8:  LPAI L04A7
L04AA:  JCZ                         ;count up to 0 (a delay of $11 loops) -> L04A7
L04AB:  LDA  RET2
L04AC:  LPAI L04B3
L04AE:  JMI                         ;the stick is below the estimate  taken if the stick is past the X register (MUX axis)
L04AF:  ADD  TMP2E                  ;above: estimate + step
L04B0:  LPAI L04B4
L04B2:  JMP

L04B3:  SUB  TMP2E                  ;below: estimate - step
L04B4:  STA  RET2
L04B5:  LDAI #$000
L04B6:  A4I  #$2
L04B7:  TST  TMP2E
L04B8:  LPAI L04C1
L04BA:  JEQ                         ;the last step (2) done  if 2 = TMP2E -> L04C1
L04BB:  LDAP                        ;TMP2E
L04BC:  SHR                         ;halve the step
L04BD:  STAP                        ;store to TMP2E
L04BE:  LPAI L049D
L04C0:  JMP

L04C1:  LDA  RET2
L04C2:  SUB  AXIS_POS               ;the change from the last reading
L04C3:  STA  TMP2E
L04C4:  LDAI #$800
L04C5:  TST  TMP2E
L04C6:  LPAI L04CC
L04C8:  JLT                         ;if TMP2E < $800 -> L04CC
L04C9:  LDAI #$000
L04CA:  SUB  TMP2E
L04CB:  STAP                        ;abs  store to TMP2E
L04CC:  LDAI #$000
L04CD:  A4I  #$7
L04CE:  TST  TMP2E
L04CF:  LPAI L04D4
L04D1:  JLT                         ;less than 7: keep the old reading (no jitter)  if TMP2E < 7 -> L04D4
L04D2:  LDA  RET2
L04D3:  STA  AXIS_POS               ;else take the new one
L04D4:  TST  XHAIR_Y
L04D5:  LPAP                        ;J = the address in XHAIR_Y
L04D6:  JMP                         ;J from RAM -> L0478, L048B

; Digital stick (input 14 low): inputs 1-4 step the stick position by 16
; each frame, kept within -$200..$200 (x) and -$180..$180 (y), and used as the
; crosshair position directly.

;------------------------------------------------------------------------------
; JOYDIGITAL - Digital stick: inputs 1-4 move the crosshair by a fixed step,
;   clamped to the screen.
;------------------------------------------------------------------------------
JOYDIGITAL:
;[static] not executed in the traces; reached by following the jumps
L04D7:  INP  $1                     ;input 1: not wired on Tailgunner (reads 1)
L04D8:  SETP $2
L04D9:  STA  RET2
L04DA:  INP  $2                     ;input 2: not wired on Tailgunner (reads 1)
L04DB:  SUBP                        ;input 2 - input 1 (each 0 = pressed): -1, 0 or +1  RET2
L04DC:  SHL
L04DD:  SHL
L04DE:  SHL
L04DF:  SHL                         ;x 16
L04E0:  ADD  STICK_X
L04E1:  STAP                        ;step the x position  store to STICK_X
L04E2:  LDAI #$200
L04E3:  TST  STICK_X
L04E4:  LPAI L04F6
L04E6:  JLT                         ;if STICK_X < $200 -> L04F6
L04E7:  LDAI #$E00
L04E8:  TST  STICK_X
L04E9:  JCZ                         ;if $E00 < STICK_X -> L04F6
L04EA:  LDAI #$800
L04EB:  TST  STICK_X
L04EC:  LPAI L04F4
L04EE:  JLT                         ;if STICK_X < $800 -> L04F4
L04EF:  LDAI #$E00
L04F0:  STAP                        ;store to STICK_X
L04F1:  LPAI L04F6
L04F3:  JMP

L04F4:  LDAI #$200
L04F5:  STAP
L04F6:  LDAP
L04F7:  STA  XHAIR_X
L04F8:  INP  $3                     ;input 3: not wired on Tailgunner (reads 1)
L04F9:  SETP $2
L04FA:  STA  RET2
L04FB:  INP  $4                     ;input 4: not wired on Tailgunner (reads 1)
L04FC:  SUBP                        ;input 4 - input 3  RET2
L04FD:  SHL
L04FE:  SHL
L04FF:  SHL
L0500:  SHL
L0501:  ADD  STICK_Y
L0502:  STAP                        ;step the y position  store to STICK_Y
L0503:  LDAI #$300
L0504:  SHR
L0505:  TST  STICK_Y
L0506:  LPAI L051B
L0508:  JLT                         ;if STICK_Y < A -> L051B
L0509:  LDAI #$D00
L050A:  ASR
L050B:  TST  STICK_Y
L050C:  JCZ                         ;if A < STICK_Y -> L051B
L050D:  LDAI #$800
L050E:  TST  STICK_Y
L050F:  LPAI L0518
L0511:  JLT                         ;if STICK_Y < $800 -> L0518
L0512:  LDAI #$D00
L0513:  ASR
L0514:  STAP                        ;store to STICK_Y
L0515:  LPAI L051B
L0517:  JMP

L0518:  LDAI #$300
L0519:  SHR
L051A:  STAP
L051B:  LDAP
L051C:  STA  XHAIR_Y
CLAMPXH:
L051D:  LDAI #$100                  ;clamp XHAIR_X to -$17C..$1A4
L051E:  A8I  #$A4
L0520:  TST  XHAIR_X
L0521:  LPAI L0537
L0523:  JLT                         ;if XHAIR_X < $1A4 -> L0537
L0524:  LDAI #$800
L0525:  TST  XHAIR_X
L0526:  LPAI L0533
L0528:  JLT                         ;if XHAIR_X < $800 -> L0533
L0529:  LDAI #$E00
L052A:  A8I  #$84
L052C:  TST  XHAIR_X
L052D:  LPAI L0536
L052F:  JLT                         ;if XHAIR_X < $E84 -> L0536
L0530:  LPAI L0537
L0532:  JMP

;[static] not executed in the traces; reached by following the jumps
L0533:  LDAI #$100
L0534:  A8I  #$A4
L0536:  STA  XHAIR_X
L0537:  LDAI #$100                  ;clamp XHAIR_Y to -$12C..$12C
L0538:  A8I  #$2C
L053A:  TST  XHAIR_Y
L053B:  LPAI CROSSHAIR
L053D:  JLT                         ;if XHAIR_Y < $12C -> CROSSHAIR
L053E:  LDAI #$800
L053F:  TST  XHAIR_Y
L0540:  LPAI L054D
L0542:  JLT                         ;if XHAIR_Y < $800 -> L054D
L0543:  LDAI #$E00
L0544:  A8I  #$D4
L0546:  TST  XHAIR_Y
L0547:  LPAI L0550
L0549:  JLT                         ;if XHAIR_Y < $ED4 -> L0550
L054A:  LPAI CROSSHAIR
L054C:  JMP

L054D:  LDAI #$100
L054E:  A8I  #$2C
L0550:  STA  XHAIR_Y
; The crosshair's screen position, the beam taken to it, then the fire button:
; a new press, with the shield down and no wait running, starts a shot.

;------------------------------------------------------------------------------
; CROSSHAIR - Position the crosshair, read the fire button and start a laser
;   shot (SHOT) on a new press when the previous shot is over.
;------------------------------------------------------------------------------
CROSSHAIR:
L0551:  LDAI #$300
L0552:  SHR
L0553:  ADD  XHAIR_Y
L0554:  SETP $6
L0555:  STA  XH_DRAW_Y              ;XH_DRAW_Y = $180 + XHAIR_Y
L0556:  SSA
L0557:  LDAP B                      ;XH_DRAW_Y
L0558:  LDAI #$200
L0559:  SETP $2
L055A:  ADD  XHAIR_X
L055B:  SETP $6
L055C:  STA  XH_DRAW_X              ;XH_DRAW_X = $200 + XHAIR_X
L055D:  S8I  #$1E                   ;- $1E: the crosshair's left end
L055F:  LPAI L055F
L0561:  JVN                         ;while the vector generator is busy -> L055F
L0562:  IV                          ;beam to it, ready for XHAIRDRAW
L0563:  LDAI #$000
L0564:  OUT  OUT_INTENSITY          ;dim
L0565:  INP  IN_FIRE                ;input 5: fire button (active low)
L0566:  SETP $6
L0567:  STA  FIRE_NOW               ;fire button now
L0568:  LDAI #$000
L0569:  TST  FIRE_WAIT
L056A:  LPAI L0573
L056C:  JEQ                         ;if FIRE_WAIT = 0 -> L0573
L056D:  LDAP                        ;FIRE_WAIT
L056E:  S4I  #$1
L056F:  STAP                        ;count down the wait between shots  store to FIRE_WAIT
L0570:  LPAI L0584
L0572:  JMP

L0573:  TST  FIRE_NOW
L0574:  LPAI L0584
L0576:  JCZ                         ;fire not pressed  if A < FIRE_NOW -> L0584
L0577:  INP  IN_SHIELD              ;input 6: shield button (active low)
L0578:  LDAI #$000
L0579:  JEQ                         ;no shot with the shield up  if IN_SHIELD = 0 -> L0584
L057A:  LDA  FIRE_NOW
L057B:  TST  FIRE_LAST
L057C:  LPAI L0584
L057E:  JEQ                         ;still held from before: a shot needs a new press  if FIRE_NOW = FIRE_LAST -> L0584
L057F:  LDAI #$000
L0580:  A4I  #$9
L0581:  STA  SHOT                   ;a shot: 9 frames of laser
L0582:  A4I  #$3
L0583:  STA  FIRE_WAIT              ;and 12 frames before the next can start
L0584:  LDA  FIRE_NOW
L0585:  STA  FIRE_LAST
; Fighter 1. Not in play: just the delay its update would have taken, so the
; frame keeps its length. FTRn_STATE 0 (flying) is updated by FTRUPDATE; from
; 3 (set by a hit) it is the explosion, counted up here until PASSCHK removes
; it at $18 (the traces see only 0 and 3-$18).
; A fighter flying away (FTRn_AWAY set) stops (speed 0) and turns away (HEADX + 1,
; HEADY + 2 each frame).

;------------------------------------------------------------------------------
; FIGHTER1 - Fighter 1 (page 3): count down its explosion, then update and draw
;   it through FTRUPDATE (return address in RET0).
;------------------------------------------------------------------------------
FIGHTER1:
L0586:  LDAI #$000
L0587:  SETP $3
L0588:  TST  FTR1_MODEL
L0589:  LPAI L05AF
L058B:  JEQ                         ;if FTR1_MODEL = 0 -> L05AF
L058C:  TST  FTR1_STATE
L058D:  LPAI L0599
L058F:  JCZ                         ;if FTR1_STATE > 0 -> L0599
L0590:  TST  FTR1_AWAY
L0591:  JEQ                         ;if FTR1_AWAY = 0 -> L0599
L0592:  STA  FTR1_SPEED
L0593:  LDA  FTR1_HEADX
L0594:  A4I  #$1
L0595:  STAP                        ;store to FTR1_HEADX
L0596:  LDA  FTR1_HEADY
L0597:  A4I  #$2
L0598:  STAP                        ;store to FTR1_HEADY
L0599:  LDAI #$000
L059A:  A4I  #$2
L059B:  TST  FTR1_STATE
L059C:  LPAI L05AC
L059E:  JCZ                         ;if 2 < FTR1_STATE -> L05AC
L059F:  LDAI #$500
L05A0:  A8I  #$B6
L05A2:  SETP $0
L05A3:  STA  RET0                   ;FTRUPDATE: return address
L05A4:  LDAI #$000
L05A5:  A8I  #$31
L05A7:  SETP $1
L05A8:  STA  OBJ_PTR                ;FTRUPDATE: the fighter (address of FTRn_X)
L05A9:  LPAI FTRUPDATE
L05AB:  JMP

L05AC:  LDA  FTR1_STATE
L05AD:  A4I  #$1
L05AE:  STAP                        ;store to FTR1_STATE
L05AF:  LDAI #$000
L05B0:  S8I  #$64
L05B2:  A4I  #$1
L05B3:  LPAI L05B2
L05B5:  JCZ                         ;count up to 0 (a delay of $64 loops) -> L05B2

;------------------------------------------------------------------------------
; XHAIRDRAW - In a game, draw the crosshair at XH_DRAW_X / XH_DRAW_Y from shape
;   table XHAIRSHP: x,y pairs ($80 = 0) are lines from the last point, $FF x y
;   moves, $FF $FF ends.
;   Reached by the jump through RAM at L0EEA.
;------------------------------------------------------------------------------
XHAIRDRAW:
L05B6:  LDAI #$000
L05B7:  SETP $6
L05B8:  TST  FTRS_LEFT
L05B9:  LPAI LASERS
L05BB:  JEQ                         ;if FTRS_LEFT = 0 -> LASERS
L05BC:  SETP $6
L05BD:  LDA  XH_DRAW_X
L05BE:  SETP $1
L05BF:  STA  OBJ_X
L05C0:  S8I  #$1E
L05C2:  STA  TMP13                  ;the beam starts at the left end (-$1E, 0)
L05C3:  SETP $6
L05C4:  LDA  XH_DRAW_Y
L05C5:  SETP $1
L05C6:  STA  OBJ_Y
L05C7:  STA  TMP14
L05C8:  LDAI #$600
L05C9:  A8I  #$15
L05CB:  STA  TMP16                  ;XHAIRSHP - 2
L05CC:  LDAI #$000
L05CD:  A8I  #$FF
L05CF:  STA  CONST_FF
L05D0:  LPAI L05D0
L05D2:  JVN                         ;while the vector generator is busy -> L05D0
L05D3:  LDA  TMP13
L05D4:  SSA
L05D5:  LDA  B,TMP14
L05D6:  IV
L05D7:  LDA  TMP16
L05D8:  A4I  #$2
L05D9:  STAP                        ;store to TMP16
L05DA:  LKP                         ;table read $0617-$0646
L05DC:  TST  CONST_FF
L05DD:  LPAI L05FF
L05DF:  JEQ                         ;if A = CONST_FF -> L05FF
L05E0:  S8I  #$80
L05E2:  SUB  TMP13
L05E3:  ADD  OBJ_X
L05E4:  STA  TMP1C                  ;line end x
L05E5:  LDA  TMP16
L05E6:  A4I  #$1
L05E7:  LKP                         ;table read $0618-$0645
L05E9:  S8I  #$80
L05EB:  SUB  TMP14
L05EC:  ADD  OBJ_Y
L05ED:  STA  TMP1D                  ;line end y
L05EE:  LDA  TMP1C
L05EF:  SSA
L05F0:  LDA  B,TMP1D
L05F1:  NV
L05F2:  ADD  TMP13
L05F3:  SSA
L05F4:  ADD  B,TMP14
L05F5:  DV                          ;one line of the crosshair
L05F6:  LDA  TMP1C
L05F7:  ADD  TMP13
L05F8:  STAP                        ;store to TMP13
L05F9:  LDA  TMP1D
L05FA:  ADD  TMP14
L05FB:  STAP                        ;its end is the next start  store to TMP14
L05FC:  LPAI L05D0
L05FE:  JMP

L05FF:  LDA  TMP16
L0600:  A4I  #$1
L0601:  STAP                        ;store to TMP16
L0602:  LKP                         ;table read $061A-$0647
L0604:  TST  CONST_FF
L0605:  LPAI LASERS
L0607:  JEQ                         ;if A = CONST_FF -> LASERS
L0608:  S8I  #$80
L060A:  ADD  OBJ_X
L060B:  STA  TMP13                  ;move: the new start
L060C:  LDA  TMP16
L060D:  A4I  #$1
L060E:  LKP                         ;table read $061B-$0643
L0610:  S8I  #$80
L0612:  ADD  OBJ_Y
L0613:  STA  TMP14
L0614:  LPAI L05D0
L0616:  JMP

;$0617-$0647, read by LKP at L05DA, L05E7, L0602, L060E
XHAIRSHP:
L0617:  .byte $9E, $80              ;line to +30, +0
L0619:  .byte $FF, $94, $76         ;move to +20, -10
L061C:  .byte $94, $8A              ;line to +20, +10
L061E:  .byte $FF, $8A, $94         ;move to +10, +20
L0621:  .byte $76, $94              ;line to -10, +20
L0623:  .byte $FF, $80, $9E         ;move to +0, +30
L0626:  .byte $80, $62              ;line to +0, -30
L0628:  .byte $FF, $8A, $6C         ;move to +10, -20
L062B:  .byte $76, $6C              ;line to -10, -20
L062D:  .byte $FF, $6C, $76         ;move to -20, -10
L0630:  .byte $6C, $8A              ;line to -20, +10
L0632:  .byte $FF, $7B, $8A         ;move to -5, +10
L0635:  .byte $85, $8A              ;line to +5, +10
L0637:  .byte $FF, $8A, $85         ;move to +10, +5
L063A:  .byte $8A, $7B              ;line to +10, -5
L063C:  .byte $FF, $85, $76         ;move to +5, -10
L063F:  .byte $7B, $76              ;line to -5, -10
L0641:  .byte $FF, $76, $7B         ;move to -10, -5
L0644:  .byte $76, $85              ;line to -10, +5
L0646:  .byte $FF, $FF              ;end

;------------------------------------------------------------------------------
; LASERS - Lasers. While a shot is on (SHOT counts 9 down to 1) the laser sound
;   plays and two beams come from the bottom corners toward the crosshair: each
;   frame a beam's front is at (16 - SHOT) / 16 of the way, so the beams close
;   in and shorten (as captured frames show). Here the left beam's front is
;   worked out and the beam taken there; FIGHTER2 runs, then LASERL draws it.
;   Input 8 (not wired) low would pulse the sound for the first frames.
;------------------------------------------------------------------------------
LASERS:
L0648:  LDAI #$000
L0649:  SETP $6
L064A:  TST  SHOT
L064B:  LPAI L06B9
L064D:  JEQ                         ;if SHOT = 0 -> L06B9
L064E:  INP  $8                     ;input 8 low would make the sound pulse  input 8: not wired on Tailgunner (reads 1)
L064F:  LDAI #$000
L0650:  LPAI L065D
L0652:  JEQ                         ;if input 8 = 0 -> L065D
L0653:  LDAI #$000
L0654:  A4I  #$6
L0655:  LDAP                        ;SHOT
L0656:  JLT                         ;the first frames: sound on  if SHOT < 6 -> L065D
L0657:  LDAI #$000
L0658:  A4I  #$1
L0659:  ANDP                        ;later: on in odd frames  SHOT
L065A:  LPAI L065F
L065C:  JMP

L065D:  LDAI #$000
L065E:  A4I  #$1
L065F:  A8I  #$1A
L0661:  OUT  OUT_SND_DATA           ;sound: laser on or off (bit 0 of A)
L0662:  SHR
L0663:  OUT  OUT_SND_A0
L0664:  SHR
L0665:  OUT  OUT_SND_A1
L0666:  SHR
L0667:  OUT  OUT_SND_A2
L0668:  SHR
L0669:  OUT  OUT_SND_STROBE
L066A:  SHR
L066B:  OUT  OUT_SND_STROBE
L066C:  LDA  SHOT                   ;front = crosshair x - SHOT x crosshair x / 16
L066D:  SSA
L066E:  LDAI B,#$000
L066F:  TST  XH_DRAW_X
L0670:  MUL
L0671:  MUL
L0672:  MUL
L0673:  MUL
L0674:  SHRB
L0675:  SSA
L0676:  STA  B,LASER_DX
L0677:  LDA  XH_DRAW_X
L0678:  SUB  LASER_DX
L0679:  SETP $0
L067A:  STA  TMP0A                  ;the left beam's front x
L067B:  SSA
L067C:  LDAI B,#$000
L067D:  SETP $6
L067E:  LDA  SHOT
L067F:  SETP $6
L0680:  TST  XH_DRAW_Y
L0681:  MUL
L0682:  MUL
L0683:  MUL
L0684:  MUL
L0685:  SHRB
L0686:  SSA
L0687:  STA  B,LASER_DY
L0688:  LDA  XH_DRAW_Y
L0689:  SUB  LASER_DY
L068A:  SETP $0
L068B:  STA  TMP0B                  ;the left beam's front y
L068C:  SSA
L068D:  LDAP B                      ;TMP0B
L068E:  LDA  TMP0A
L068F:  LPAI L0691
L0691:  JVN                         ;while the vector generator is busy -> L0691
L0692:  IV                          ;beam to the front; FIGHTER2 runs before LASERL draws

;------------------------------------------------------------------------------
; FIGHTER2 - Fighter 2 (page 4): as FIGHTER1.
;------------------------------------------------------------------------------
FIGHTER2:
L0693:  LDAI #$000
L0694:  SETP $4
L0695:  TST  FTR2_MODEL
L0696:  LPAI L06CD
L0698:  JEQ                         ;if FTR2_MODEL = 0 -> L06CD
L0699:  TST  FTR2_STATE
L069A:  LPAI L06A6
L069C:  JCZ                         ;if FTR2_STATE > 0 -> L06A6
L069D:  TST  FTR2_AWAY
L069E:  JEQ                         ;if FTR2_AWAY = 0 -> L06A6
L069F:  STA  FTR2_SPEED
L06A0:  LDA  FTR2_HEADX
L06A1:  A4I  #$2
L06A2:  STAP                        ;store to FTR2_HEADX
L06A3:  LDA  FTR2_HEADY
L06A4:  S4I  #$1
L06A5:  STAP                        ;store to FTR2_HEADY
L06A6:  LDAI #$000
L06A7:  A4I  #$2
L06A8:  TST  FTR2_STATE
L06A9:  LPAI L06CA
L06AB:  JCZ                         ;if 2 < FTR2_STATE -> L06CA
L06AC:  LDAI #$600
L06AD:  A8I  #$D4
L06AF:  SETP $0
L06B0:  STA  RET0                   ;FTRUPDATE: return address
L06B1:  LDAI #$000
L06B2:  A8I  #$41
L06B4:  SETP $1
L06B5:  STA  OBJ_PTR                ;FTRUPDATE: the fighter (address of FTRn_X)
L06B6:  LPAI FTRUPDATE
L06B8:  JMP

L06B9:  LDAI #$000
L06BA:  A8I  #$1A
L06BC:  OUT  OUT_SND_DATA           ;sound: laser off
L06BD:  SHR
L06BE:  OUT  OUT_SND_A0
L06BF:  SHR
L06C0:  OUT  OUT_SND_A1
L06C1:  SHR
L06C2:  OUT  OUT_SND_A2
L06C3:  SHR
L06C4:  OUT  OUT_SND_STROBE
L06C5:  SHR
L06C6:  OUT  OUT_SND_STROBE
L06C7:  LPAI FIGHTER2
L06C9:  JMP

L06CA:  LDA  FTR2_STATE
L06CB:  A4I  #$1
L06CC:  STAP                        ;store to FTR2_STATE
L06CD:  LDAI #$000
L06CE:  S8I  #$64
L06D0:  A4I  #$1
L06D1:  LPAI L06D0
L06D3:  JCZ                         ;count up to 0 (a delay of $64 loops) -> L06D0

;------------------------------------------------------------------------------
; LASERL - Draw the left beam (with a shot on): a thin closed bolt of four
;   segments from its front (TMP0A / TMP0B), out toward the half-way point to
;   the crosshair and back. Input 13 (not wired) low would draw it as one
;   vector instead (that path never ran in the traces).
;   Reached by the jump through RAM at L0EEA.
;------------------------------------------------------------------------------
LASERL:
L06D4:  LDAI #$000
L06D5:  SETP $6
L06D6:  TST  SHOT
L06D7:  LPAI FIGHTER3
L06D9:  JEQ                         ;if SHOT = 0 -> FIGHTER3
L06DA:  INP  $D                     ;input 13: not wired on Tailgunner (reads 1)
L06DB:  A4I  #$1
L06DC:  LPAI BOLT
L06DE:  JEQ                         ;if input 13 = 1 -> BOLT
;[static] not executed in the traces; reached by following the jumps
L06DF:  OUT  OUT_INTENSITY          ;vector intensity: A bit 0 = 1 bright, 0 dim
L06E0:  LDAI #$F00
L06E1:  A8I  #$C0
L06E3:  SETP $0
L06E4:  STA  TMP05
L06E5:  SSA
L06E6:  LDAI B,#$000
L06E7:  SETP $6
L06E8:  LDA  SHOT
L06E9:  SETP $0
L06EA:  TST  TMP05
L06EB:  MUL
L06EC:  MUL
L06ED:  MUL
L06EE:  MUL
L06EF:  SHRB
L06F0:  SSA
L06F1:  ADD  B,TMP0A
L06F2:  SSA
L06F3:  STA  B,TMP05
L06F4:  LDA  TMP0B
L06F5:  STA  TMP06
L06F6:  SSA
L06F7:  LDAP B                      ;TMP06
L06F8:  LDA  TMP05
L06F9:  IV
L06FA:  SETP $6
L06FB:  SUB  XH_DRAW_X
L06FC:  ASR
L06FD:  SETP $0
L06FE:  STA  TMP07
L06FF:  LDAI #$800
L0700:  LDAP                        ;TMP07
L0701:  LPAI L0706
L0703:  JLT                         ;if TMP07 < $800 -> L0706
L0704:  LDAI #$000
L0705:  SUBP                        ;TMP07
L0706:  STA  TMP0E
L0707:  LDA  TMP06
L0708:  SETP $6
L0709:  SUB  XH_DRAW_Y
L070A:  ASR
L070B:  SETP $0
L070C:  STA  TMP08
L070D:  SSA
L070E:  LDAP B                      ;TMP08
L070F:  LDAI #$800
L0710:  LDAP                        ;TMP08
L0711:  LPAI L0716
L0713:  JLT                         ;if TMP08 < $800 -> L0716
L0714:  LDAI #$000
L0715:  SUBP                        ;TMP08
L0716:  ADD  TMP0E
L0717:  S4I  #$3
L0718:  LPAI BEAMDONE
L071A:  JCZ                         ;if A < 3 -> BEAMDONE
L071B:  LDA  TMP07
L071C:  NV
L071D:  ADD  TMP05
L071E:  SSA
L071F:  ADD  B,TMP06
L0720:  DV
L0721:  LPAI BEAMDONE
L0723:  JMP


;------------------------------------------------------------------------------
; BOLT - The bolt: TMP07 / TMP08 = half the way from the front to the
;   crosshair, TMP0E = a quarter of that across; the four points are visited
;   through BEAMSEG, TMP0C naming the next step and TMP01 where to go when the
;   bolt is done.
;------------------------------------------------------------------------------
BOLT:
L0724:  LDAI #$000
L0725:  A4I  #$1
L0726:  OUT  OUT_INTENSITY          ;bright
L0727:  SETP $0
L0728:  LDA  TMP0A
L0729:  SETP $6
L072A:  SUB  XH_DRAW_X
L072B:  ASR
L072C:  SETP $0
L072D:  STA  TMP07
L072E:  LDA  TMP0B
L072F:  SETP $6
L0730:  SUB  XH_DRAW_Y
L0731:  ASR
L0732:  SETP $0
L0733:  STA  TMP08
L0734:  LDA  TMP07
L0735:  ASR
L0736:  ASR
L0737:  STA  TMP0E
L0738:  LDAI #$700
L0739:  A8I  #$A4
L073B:  STA  TMP01
L073C:  LDA  TMP0A
L073D:  STA  TMP02
L073E:  LDA  TMP0B
L073F:  STA  TMP03
L0740:  ADD  TMP08
L0741:  STA  TMP09
L0742:  LDA  TMP0A
L0743:  ADD  TMP07
L0744:  ADD  TMP0E
L0745:  STA  TMP04
L0746:  LDAI #$700
L0747:  A8I  #$81

;------------------------------------------------------------------------------
; BEAMSEG - Draw one bolt segment from TMP02 / TMP03 to TMP04 / TMP09, then go
;   where TMP0C says (BEAMNEXT).
;------------------------------------------------------------------------------
BEAMSEG:
L0749:  STA  TMP0C
L074A:  LDA  TMP02
L074B:  SSA
L074C:  LDA  B,TMP03
L074D:  LPAI L074F
L074F:  JVN                         ;while the vector generator is busy -> L074F
L0750:  IV
L0751:  LDAI #$000
L0752:  S8I  #$0B
L0754:  A4I  #$1
L0755:  LPAI L0754
L0757:  JCZ                         ;count up to 0 (a delay of $B loops) -> L0754
L0758:  LDA  TMP09
L0759:  SUB  TMP03
L075A:  STA  TMP0D
L075B:  SSA
L075C:  LDAP B                      ;TMP0D
L075D:  LDAI #$800
L075E:  LDAP                        ;TMP0D
L075F:  LPAI L0764
L0761:  JLT                         ;if TMP0D < $800 -> L0764
L0762:  LDAI #$000
L0763:  SUBP                        ;TMP0D
L0764:  STAP
L0765:  LDA  TMP04
L0766:  SUB  TMP02
L0767:  STA  TMP0F
L0768:  LDAI #$800
L0769:  LDAP                        ;TMP0F
L076A:  LPAI L076F
L076C:  JLT                         ;if TMP0F < $800 -> L076F
L076D:  LDAI #$000
L076E:  SUBP                        ;TMP0F
L076F:  ADD  TMP0D
L0770:  S4I  #$3
L0771:  LPAI L077A
L0773:  JCZ                         ;if A < 3 -> L077A
L0774:  LDA  TMP0F
L0775:  NV
L0776:  ADD  TMP02
L0777:  SSA
L0778:  ADD  B,TMP03
L0779:  DV
L077A:  LDA  TMP04
L077B:  STA  TMP02
L077C:  LDA  TMP09
L077D:  STA  TMP03
L077E:  TST  TMP0C
L077F:  LPAP                        ;J = the address in TMP0C
BEAMNEXT:
L0780:  JMP                         ;J from RAM -> BOLTSTEP2, BOLTSTEP3, BEAMDONE, AFTERFTR


;------------------------------------------------------------------------------
; BOLTSTEP1 - Bolt point 2: a quarter of the way.
;------------------------------------------------------------------------------
BOLTSTEP1:
L0781:  LDA  TMP07
L0782:  ASR
L0783:  ADD  TMP0A
L0784:  STA  TMP04
L0785:  LDA  TMP08
L0786:  ASR
L0787:  ADD  TMP0B
L0788:  STA  TMP09
L0789:  LDAI #$700
L078A:  A8I  #$8F
L078C:  LPAI BEAMSEG
L078E:  JMP


;------------------------------------------------------------------------------
; BOLTSTEP2 - Bolt point 3: half way, offset the other side.
;   Reached by the jump through RAM at BEAMNEXT.
;------------------------------------------------------------------------------
BOLTSTEP2:
L078F:  LDA  TMP0A
L0790:  ADD  TMP07
L0791:  SUB  TMP0E
L0792:  STA  TMP04
L0793:  LDA  TMP08
L0794:  ADD  TMP0B
L0795:  STA  TMP09
L0796:  LDAI #$700
L0797:  A8I  #$9C
L0799:  LPAI BEAMSEG
L079B:  JMP


;------------------------------------------------------------------------------
; BOLTSTEP3 - Bolt point 4: back to the front; then TMP01's step.
;   Reached by the jump through RAM at BEAMNEXT.
;------------------------------------------------------------------------------
BOLTSTEP3:
L079C:  LDA  TMP0A
L079D:  STA  TMP04
L079E:  LDA  TMP0B
L079F:  STA  TMP09
L07A0:  LDA  TMP01
L07A1:  LPAI BEAMSEG
L07A3:  JMP


;------------------------------------------------------------------------------
; BEAMDONE - After the left bolt: the right beam's front, (16 - SHOT) / 16 of
;   the way from the bottom-right corner ($400) to the crosshair, and the beam
;   taken there; FIGHTER3 runs, then LASERR draws it.
;   Reached by the jump through RAM at BEAMNEXT.
;------------------------------------------------------------------------------
BEAMDONE:
L07A4:  LDAI #$400
L07A5:  SETP $6
L07A6:  SUB  XH_DRAW_X
L07A7:  STA  LASER_DX
L07A8:  SSA
L07A9:  LDAI B,#$000
L07AA:  LDA  SHOT
L07AB:  TST  LASER_DX
L07AC:  MUL
L07AD:  MUL
L07AE:  MUL
L07AF:  MUL
L07B0:  SHRB
L07B1:  SSA
L07B2:  STA  B,LASER_DX
L07B3:  LDAP                        ;LASER_DX
L07B4:  ADD  XH_DRAW_X
L07B5:  SETP $0
L07B6:  STA  TMP0A
L07B7:  SSA
L07B8:  LDA  B,TMP0B
L07B9:  LPAI L07BB
L07BB:  JVN                         ;while the vector generator is busy -> L07BB
L07BC:  IV

;------------------------------------------------------------------------------
; FIGHTER3 - Fighter 3 (page 5): as FIGHTER1.
;------------------------------------------------------------------------------
FIGHTER3:
L07BD:  LDAI #$000
L07BE:  SETP $5
L07BF:  TST  FTR3_MODEL
L07C0:  LPAI L07E6
L07C2:  JEQ                         ;if FTR3_MODEL = 0 -> L07E6
L07C3:  TST  FTR3_STATE
L07C4:  LPAI L07D0
L07C6:  JCZ                         ;if FTR3_STATE > 0 -> L07D0
L07C7:  TST  FTR3_AWAY
L07C8:  JEQ                         ;if FTR3_AWAY = 0 -> L07D0
L07C9:  STA  FTR3_SPEED
L07CA:  LDA  FTR3_HEADX
L07CB:  S4I  #$2
L07CC:  STAP                        ;store to FTR3_HEADX
L07CD:  LDA  FTR3_HEADY
L07CE:  A4I  #$1
L07CF:  STAP                        ;store to FTR3_HEADY
L07D0:  LDAI #$000
L07D1:  A4I  #$2
L07D2:  TST  FTR3_STATE
L07D3:  LPAI L07E3
L07D5:  JCZ                         ;if 2 < FTR3_STATE -> L07E3
L07D6:  LDAI #$700
L07D7:  A8I  #$ED
L07D9:  SETP $0
L07DA:  STA  RET0                   ;FTRUPDATE: return address
L07DB:  LDAI #$000
L07DC:  A8I  #$51
L07DE:  SETP $1
L07DF:  STA  OBJ_PTR                ;FTRUPDATE: the fighter (address of FTRn_X)
L07E0:  LPAI FTRUPDATE
L07E2:  JMP

L07E3:  LDA  FTR3_STATE
L07E4:  A4I  #$1
L07E5:  STAP                        ;store to FTR3_STATE
L07E6:  LDAI #$000
L07E7:  S8I  #$64
L07E9:  A4I  #$1
L07EA:  LPAI L07E9
L07EC:  JCZ                         ;count up to 0 (a delay of $64 loops) -> L07E9

;------------------------------------------------------------------------------
; LASERR - Draw the right beam: the same bolt as LASERL (BOLT), from the right
;   beam's front.
;   Reached by the jump through RAM at L0EEA.
;------------------------------------------------------------------------------
LASERR:
L07ED:  LDAI #$000
L07EE:  SETP $6
L07EF:  TST  SHOT
L07F0:  LPAI AFTERFTR
L07F2:  JEQ                         ;if SHOT = 0 -> AFTERFTR
L07F3:  INP  $D                     ;input 13: not wired on Tailgunner (reads 1)
L07F4:  A4I  #$1
L07F5:  LPAI L083E
L07F7:  JEQ                         ;if input 13 = 1 -> L083E
;[static] not executed in the traces; reached by following the jumps
L07F8:  LDAI #$000
L07F9:  A8I  #$40
L07FB:  SETP $0
L07FC:  STA  TMP05
L07FD:  SSA
L07FE:  LDAI B,#$000
L07FF:  SETP $6
L0800:  LDA  SHOT
L0801:  SETP $0
L0802:  TST  TMP05
L0803:  MUL
L0804:  MUL
L0805:  MUL
L0806:  MUL
L0807:  SHRB
L0808:  SSA
L0809:  ADD  B,TMP0A
L080A:  SSA
L080B:  STA  B,TMP05
L080C:  LDA  TMP0B
L080D:  STA  TMP06
L080E:  SSA
L080F:  LDAP B                      ;TMP06
L0810:  LDA  TMP05
L0811:  IV
L0812:  SETP $0
L0813:  LDA  TMP05
L0814:  SETP $6
L0815:  SUB  XH_DRAW_X
L0816:  ASR
L0817:  SETP $0
L0818:  STA  TMP07
L0819:  LDAI #$800
L081A:  LDAP                        ;TMP07
L081B:  LPAI L0820
L081D:  JLT                         ;if TMP07 < $800 -> L0820
L081E:  LDAI #$000
L081F:  SUBP                        ;TMP07
L0820:  STA  TMP0E
L0821:  LDA  TMP06
L0822:  SETP $6
L0823:  SUB  XH_DRAW_Y
L0824:  ASR
L0825:  SETP $0
L0826:  STA  TMP08
L0827:  SSA
L0828:  LDAP B                      ;TMP08
L0829:  LDAI #$800
L082A:  LDAP                        ;TMP08
L082B:  LPAI L0830
L082D:  JLT                         ;if TMP08 < $800 -> L0830
L082E:  LDAI #$000
L082F:  SUBP                        ;TMP08
L0830:  ADD  TMP0E
L0831:  S4I  #$3
L0832:  LPAI AFTERFTR
L0834:  JCZ                         ;if A < 3 -> AFTERFTR
L0835:  LDA  TMP07
L0836:  NV
L0837:  ADD  TMP05
L0838:  SSA
L0839:  ADD  B,TMP06
L083A:  DV
L083B:  LPAI AFTERFTR
L083D:  JMP

L083E:  SETP $0
L083F:  LDA  TMP0A
L0840:  SETP $6
L0841:  SUB  XH_DRAW_X
L0842:  ASR
L0843:  SETP $0
L0844:  STA  TMP07
L0845:  LDA  TMP0B
L0846:  SETP $6
L0847:  SUB  XH_DRAW_Y
L0848:  ASR
L0849:  SETP $0
L084A:  STA  TMP08
L084B:  LDA  TMP07
L084C:  ASR
L084D:  ASR
L084E:  STA  TMP0E
L084F:  LDAI #$800
L0850:  A8I  #$55
L0852:  LPAI L073B
L0854:  JMP


;------------------------------------------------------------------------------
; AFTERFTR - After the fighters: count the shot down; in a game the explosion
;   sound plays while any fighter's FTRn_STATE is 3-7 (the first frames of its
;   explosion), else it is turned off; then on to bank 1.
;   Reached by the jump through RAM at BEAMNEXT.
;------------------------------------------------------------------------------
AFTERFTR:
L0855:  LDAI #$000
L0856:  SETP $6
L0857:  LDA  SHOT
L0858:  LPAI L085D
L085A:  JEQ                         ;if SHOT = 0 -> L085D
L085B:  S4I  #$1
L085C:  STAP                        ;store to SHOT
L085D:  LDAI #$000
L085E:  SETP $6
L085F:  TST  FTRS_LEFT
L0860:  LPAI L08ED
L0862:  JEQ                         ;if FTRS_LEFT = 0 -> L08ED
L0863:  A4I  #$2
L0864:  SETP $3
L0865:  TST  FTR1_STATE
L0866:  LPAI L088E
L0868:  JLT                         ;if FTR1_STATE < 2 -> L088E
L0869:  A4I  #$5
L086A:  TST  FTR1_STATE
L086B:  JCZ                         ;if 7 < FTR1_STATE -> L088E
L086C:  LPAI L0898
L086E:  JMP


;------------------------------------------------------------------------------
; NOSHIELD - Shield down: shield and bounce sounds off; on to the stick.
;------------------------------------------------------------------------------
NOSHIELD:
L086F:  LDAI #$000
L0870:  A8I  #$18
L0872:  OUT  OUT_SND_DATA           ;sound: shield off
L0873:  SHR
L0874:  OUT  OUT_SND_A0
L0875:  SHR
L0876:  OUT  OUT_SND_A1
L0877:  SHR
L0878:  OUT  OUT_SND_A2
L0879:  SHR
L087A:  OUT  OUT_SND_STROBE
L087B:  SHR
L087C:  OUT  OUT_SND_STROBE
L087D:  LDAI #$000
L087E:  A8I  #$16
L0880:  OUT  OUT_SND_DATA           ;sound: bounce off
L0881:  SHR
L0882:  OUT  OUT_SND_A0
L0883:  SHR
L0884:  OUT  OUT_SND_A1
L0885:  SHR
L0886:  OUT  OUT_SND_A2
L0887:  SHR
L0888:  OUT  OUT_SND_STROBE
L0889:  SHR
L088A:  OUT  OUT_SND_STROBE
L088B:  LPAI JOYSTICK
L088D:  JMP

L088E:  LDAI #$000
L088F:  A4I  #$2
L0890:  SETP $4
L0891:  TST  FTR2_STATE
L0892:  LPAI L08A9
L0894:  JLT                         ;if FTR2_STATE < 2 -> L08A9
L0895:  A4I  #$5
L0896:  TST  FTR2_STATE
L0897:  JCZ                         ;if 7 < FTR2_STATE -> L08A9
L0898:  LDAI #$000
L0899:  A8I  #$1F
L089B:  OUT  OUT_SND_DATA           ;sound: explosion on
L089C:  SHR
L089D:  OUT  OUT_SND_A0
L089E:  SHR
L089F:  OUT  OUT_SND_A1
L08A0:  SHR
L08A1:  OUT  OUT_SND_A2
L08A2:  SHR
L08A3:  OUT  OUT_SND_STROBE
L08A4:  SHR
L08A5:  OUT  OUT_SND_STROBE
L08A6:  LPAI TOBANK1
L08A8:  JMP

L08A9:  LDAI #$000
L08AA:  A4I  #$2
L08AB:  SETP $5
L08AC:  TST  FTR3_STATE
L08AD:  LPAI L08ED
L08AF:  JLT                         ;if FTR3_STATE < 2 -> L08ED
L08B0:  A4I  #$5
L08B1:  TST  FTR3_STATE
L08B2:  JCZ                         ;if 7 < FTR3_STATE -> L08ED
L08B3:  LPAI L0898
L08B5:  JMP


;------------------------------------------------------------------------------
; ENDPASS - After the stars. With the credit screen up (CREDIT_FLAG) straight
;   on to bank 1; with a fighter in play, MOVEFTR and the rest of the pass;
;   with none: in a game the next wave or the hyperspace jump (L02DE); in
;   attract the title sequence (L02B6), started here when it is not running
;   (TITLE_STATE = 1, TITLE_Z = $F00, TITLE_ANGLE = $10).
;------------------------------------------------------------------------------
ENDPASS:
L08B6:  NOP
L08B7:  LDAI #$000
L08B8:  SETP $7
L08B9:  TST  CREDIT_FLAG
L08BA:  LPAI L08ED
L08BC:  JCZ                         ;if CREDIT_FLAG > 0 -> L08ED
L08BD:  SETP $3
L08BE:  TST  FTR1_MODEL
L08BF:  LPAI MOVEFTR
L08C1:  JCZ                         ;if FTR1_MODEL > 0 -> MOVEFTR
L08C2:  SETP $4
L08C3:  TST  FTR2_MODEL
L08C4:  JCZ                         ;if FTR2_MODEL > 0 -> MOVEFTR
L08C5:  SETP $5
L08C6:  TST  FTR3_MODEL
L08C7:  JCZ                         ;if FTR3_MODEL > 0 -> MOVEFTR
L08C8:  SETP $7
L08C9:  TST  TITLE_STATE
L08CA:  LPAI L02B6
L08CC:  JCZ                         ;if TITLE_STATE > 0 -> L02B6
L08CD:  SETP $6
L08CE:  TST  FTRS_LEFT
L08CF:  LPAI L02DE
L08D1:  JCZ                         ;if FTRS_LEFT > 0 -> L02DE
L08D2:  LDAI #$000
L08D3:  A8I  #$14
L08D5:  OUT  OUT_SND_DATA           ;sound: hyperspace off
L08D6:  SHR
L08D7:  OUT  OUT_SND_A0
L08D8:  SHR
L08D9:  OUT  OUT_SND_A1
L08DA:  SHR
L08DB:  OUT  OUT_SND_A2
L08DC:  SHR
L08DD:  OUT  OUT_SND_STROBE
L08DE:  SHR
L08DF:  OUT  OUT_SND_STROBE
L08E0:  LDAI #$000
L08E1:  SETP $7
L08E2:  STA  WAVE_TIMER
L08E3:  LDAI #$F00
L08E4:  SETP $7
L08E5:  STA  TITLE_Z
L08E6:  LDAI #$000
L08E7:  A8I  #$10
L08E9:  STA  TITLE_ANGLE
L08EA:  LDAI #$000
L08EB:  A4I  #$1
L08EC:  STA  TITLE_STATE
L08ED:  LDAI #$000
L08EE:  A8I  #$1E
L08F0:  OUT  OUT_SND_DATA           ;sound: explosion off
L08F1:  SHR
L08F2:  OUT  OUT_SND_A0
L08F3:  SHR
L08F4:  OUT  OUT_SND_A1
L08F5:  SHR
L08F6:  OUT  OUT_SND_A2
L08F7:  SHR
L08F8:  OUT  OUT_SND_STROBE
L08F9:  SHR
L08FA:  OUT  OUT_SND_STROBE

;------------------------------------------------------------------------------
; TOBANK1 - T4K to bank 1: DRAWFTRS, returning to DRAWHUD (RET0 = $600, in bank
;   1).
;------------------------------------------------------------------------------
TOBANK1:
L08FB:  LDAI #$600
L08FC:  A8I  #$00
L08FE:  SETP $0
L08FF:  STA  RET0                   ;DRAWFTRS: return address
L0900:  LPAI DRAWFTRS               ;T4K to bank 1
L0902:  SETP $2
L0903:  T4K


;------------------------------------------------------------------------------
; READDIPS - Read the three shield-points switches into SHLD_START (0-7).
;------------------------------------------------------------------------------
READDIPS:
L0904:  SSA
L0905:  INP  B,SW_SHIELD_HI         ;switch 1: DIP bit 5: shield points, high bit (with SW_SHIELD_LO0/LO1)
L0906:  SSA
L0907:  SHL  B                      ;the shield setting: SW_SHIELD_HI x 4
L0908:  SETP $8
L0909:  SSA
L090A:  STA  B,SHLD_START
L090B:  SSA
L090C:  INP  B,SW_SHIELD_LO0        ;switch 4: DIP bit 0: shield points, low bit 0
L090D:  SSA
L090E:  ADDP B                      ;+ SW_SHIELD_LO0 x 2  SHLD_START
L090F:  SSA
L0910:  SHL  B
L0911:  SSA
L0912:  STAP B                      ;store to SHLD_START
L0913:  SSA
L0914:  INP  B,SW_SHIELD_LO1        ;switch 5: DIP bit 1: shield points, low bit 1
L0915:  SSA
L0916:  ADDP B                      ;+ SW_SHIELD_LO1: 0-7 (MAME's $02 gives 1 = 20 points, $01 2 = 30, $20 4 = 50)  SHLD_START
L0917:  SSA
L0918:  STAP B                      ;store to SHLD_START
L0919:  LPAI INIT2
L091B:  JMP

;$091C-$0BFF, read by LKP at L002A
SHIELDTAB:
L091C:  .byte $15, $20, $30, $40, $50, $60, $70, $80  ;DIP setting 0-7: 15 20 30 40 50 60 70 80 shield points (BCD)
; Bytes $0924-$0BFF are development-system leftovers, not part of the game.
DEVJUNK0:
L0924:  .byte $E2, $FF, $0D, $CA, $30, $09, $36, $20
L092C:  .byte $23, $C3, $26, $09, $0E, $04, $FE, $2E
L0934:  .byte $C2, $4B, $09, $21, $65, $00, $CD, $D7
L093C:  .byte $0B, $FE, $0D, $CA, $4B, $09, $77, $23
L0944:  .byte $0D, $CA, $A5, $0B, $C3, $3A, $09, $0D
L094C:  .byte $CA, $55, $09, $36, $20, $23, $C3, $4B
L0954:  .byte $09, $36, $00, $C3, $FE, $06, $CD, $41
L095C:  .byte $08, $CD, $57, $08, $DA, $FE, $06, $0A
L0964:  .byte $03, $77, $23, $C3, $5D, $09, $21, $65
L096C:  .byte $00, $7E, $FE, $48, $C0, $23, $7E, $FE
L0974:  .byte $45, $C0, $23, $7E, $FE, $58, $C9, $EB
L097C:  .byte $2A, $81, $0F, $7D, $93, $7C, $9A, $EB
L0984:  .byte $C9, $CD, $7B, $09, $D0, $22, $81, $0F
L098C:  .byte $C9, $E5, $21, $00, $00, $CD, $7B, $09
L0994:  .byte $E1, $C9, $CD, $8A, $0C, $21, $00, $00
L099C:  .byte $CA, $A6, $09, $3D, $C2, $A5, $0B, $CD
L09A4:  .byte $60, $0C, $E5, $CD, $6B, $07, $FE, $FF
L09AC:  .byte $CA, $A5, $0B, $CD, $6A, $09, $CA, $DB
L09B4:  .byte $09, $E1, $11, $00, $01, $19, $E5, $11
L09BC:  .byte $5C, $00, $0E, $14, $CD, $A2, $06, $E1
L09C4:  .byte $B7, $C2, $40, $0A, $11, $80, $00, $0E
L09CC:  .byte $80, $1A, $13, $77, $23, $0D, $C2, $CD
L09D4:  .byte $09, $CD, $85, $09, $C3, $BA, $09, $CD
L09DC:  .byte $6E, $0B, $FE, $1A, $CA, $A5, $0B, $DE
L09E4:  .byte $3A, $C2, $DB, $09, $57, $E1, $E5, $CD
L09EC:  .byte $20, $0A, $5F, $CD, $20, $0A, $F5, $CD
L09F4:  .byte $20, $0A, $C1, $4F, $09, $7B, $B7, $C2
L09FC:  .byte $06, $0A, $60, $69, $22, $B3, $0F, $C3
L0A04:  .byte $40, $0A, $CD, $20, $0A, $CD, $20, $0A
L0A0C:  .byte $77, $23, $1D, $C2, $09, $0A, $CD, $20
L0A14:  .byte $0A, $F5, $CD, $85, $09, $F1, $C2, $A5
L0A1C:  .byte $0B, $C3, $DB, $09, $C5, $E5, $D5, $CD
L0A24:  .byte $6E, $0B, $CD, $53, $0C, $07, $07, $07
L0A2C:  .byte $07, $E6, $F0, $F5, $CD, $6E, $0B, $CD
L0A34:  .byte $53, $0C, $C1, $B0, $47, $D1, $82, $57
L0A3C:  .byte $78, $E1, $C1, $C9, $0E, $0C, $CD, $A2
L0A44:  .byte $06, $21, $69, $0A, $7E, $B7, $CA, $54
L0A4C:  .byte $0A, $CD, $C1, $0B, $23, $C3, $48, $0A
L0A54:  .byte $CD, $0F, $0C, $2A, $81, $0F, $CD, $28
L0A5C:  .byte $0C, $CD, $BF, $0B, $2A, $B3, $0F, $CD
L0A64:  .byte $28, $0C, $C3, $FE, $06, $0D, $0A, $4E
L0A6C:  .byte $45, $58, $54, $20, $20, $50, $43, $00
L0A74:  .byte $CD, $8A, $0C, $3D, $C2, $A5, $0B, $CD
L0A7C:  .byte $60, $0C, $CD, $0F, $0C, $E5, $CD, $28
L0A84:  .byte $0C, $CD, $BF, $0B, $E1, $7E, $E5, $CD
L0A8C:  .byte $FF, $0B, $CD, $BF, $0B, $CD, $B0, $0B
L0A94:  .byte $CD, $D7, $0B, $E1, $FE, $0D, $CA, $B5
L0A9C:  .byte $0A, $FE, $2E, $CA, $FE, $06, $E5, $CD
L0AA4:  .byte $8D, $0C, $3D, $C2, $A5, $0B, $CD, $60
L0AAC:  .byte $0C, $7C, $B7, $C2, $A5, $0B, $7D, $E1
L0AB4:  .byte $77, $23, $C3, $7E, $0A, $AF, $C3, $BF
L0ABC:  .byte $0A, $3E, $FF, $32, $46, $0F, $CD, $8A
L0AC4:  .byte $0C, $21, $00, $00, $CA, $D8, $0A, $3D
L0ACC:  .byte $C2, $A5, $0B, $CD, $60, $0C, $7D, $B4
L0AD4:  .byte $CA, $A5, $0B, $2B, $22, $47, $0F, $CD
L0ADC:  .byte $3E, $0D, $C3, $85, $08, $CD, $D7, $0B
L0AE4:  .byte $FE, $0D, $C2, $EF, $0A, $CD, $3E, $0D
L0AEC:  .byte $C3, $FE, $06, $01, $0B, $00, $21, $AD
L0AF4:  .byte $0D, $BE, $CA, $02, $0B, $23, $04, $0D
L0AFC:  .byte $C2, $F5, $0A, $C3, $A5, $0B, $CD, $D7
L0B04:  .byte $0B, $FE, $0D, $C2, $A5, $0B, $C5, $CD
L0B0C:  .byte $0F, $0C, $CD, $14, $0D, $CD, $BF, $0B
L0B14:  .byte $CD, $B0, $0B, $CD, $8A, $0C, $B7, $CA
L0B1C:  .byte $FE, $06, $3D, $C2, $A5, $0B, $CD, $60
L0B24:  .byte $0C, $C1, $78, $FE, $05, $D2, $53, $0B
L0B2C:  .byte $7C, $B7, $C2, $A5, $0B, $7D, $FE, $02
L0B34:  .byte $D2, $A5, $0B, $CD, $DD, $0C, $67, $41
L0B3C:  .byte $3E, $FE, $CD, $4D, $0B, $A4, $41, $67
L0B44:  .byte $7D, $CD, $4D, $0B, $B4, $12, $C3, $FE
L0B4C:  .byte $06, $05, $C8, $07, $C3, $4D, $0B, $C2
L0B54:  .byte $63, $0B, $7C, $B7, $C2, $A5, $0B, $7D
L0B5C:  .byte $21, $AE, $0F, $77, $C3, $FE, $06, $E5
L0B64:  .byte $CD, $FB, $0C, $D1, $73, $23, $72, $C3
L0B6C:  .byte $FE, $06, $E5, $D5, $C5, $3A, $5B, $00
L0B74:  .byte $E6, $7F, $CA, $8E, $0B, $16, $00, $5F
L0B7C:  .byte $21, $80, $00, $19, $7E, $FE, $1A, $CA
L0B84:  .byte $A0, $0B, $21, $5B, $00, $34, $B7, $C3
L0B8C:  .byte $A1, $0B, $0E, $14, $11, $5C, $00, $CD
L0B94:  .byte $A2, $06, $B7, $C2, $A0, $0B, $32, $5B
L0B9C:  .byte $00, $C3, $79, $0B, $37, $C1, $D1, $E1
L0BA4:  .byte $C9, $CD, $0F, $0C, $3E, $3F, $CD, $C1
L0BAC:  .byte $0B, $C3, $FE, $06, $0E, $0A, $11, $5F
L0BB4:  .byte $0F, $CD, $A2, $06, $21, $61, $0F, $22
L0BBC:  .byte $5D, $0F, $C9, $3E, $20, $E5, $D5, $C5
L0BC4:  .byte $5F, $0E, $02, $CD, $A2, $06, $C1, $D1
L0BCC:  .byte $E1, $C9, $FE, $7F, $C8, $FE, $61, $D8
L0BD4:  .byte $E6, $5F, $C9, $E5, $21, $60, $0F, $7E
L0BDC:  .byte $B7, $3E, $0D, $CA, $EE, $0B, $35, $2A
L0BE4:  .byte $5D, $0F, $7E, $23, $22, $5D, $0F, $CD
L0BEC:  .byte $CE, $0B, $E1, $C9, $FE, $0A, $D2, $FA
L0BF4:  .byte $0B, $C6, $30, $C3, $C1, $0B, $C6, $37
L0BFC:  .byte $C3, $C1, $0B, $F5

;------------------------------------------------------------------------------
; FTRUPDATE - Update one flying fighter. OBJ_PTR walks its record (from
;   FTRn_X). Steering: the offset to the destination (FTRn_DESTX/Y) / 16,
;   clamped to -$1E..$1E, is the angle to head for, turned round ($40 - it)
;   once the fighter is nearer than its destination depth; each heading
;   (FTRn_HEADX/Y) moves one step toward it. Motion: dx = speed sin(hx)
;   cos(hy), dy = speed sin(hy), and z goes down by speed cos(hx) cos(hy)
;   (9-step MUL chains on the SINCOS0 values). Then the projection (PROJDIV /
;   PROJECT, depth z / 2) gives FTRn_SCRX/Y, and HITTEST. Returns through RET0.
;------------------------------------------------------------------------------
FTRUPDATE:
L0C00:  SETP $1
L0C01:  WS   OBJ_PTR                ;I = the address in OBJ_PTR
L0C02:  LDAP                        ;[OBJ_PTR]
L0C03:  STA  OBJ_X                  ;fetch the record: x, y, z,
L0C04:  LDA  OBJ_PTR
L0C05:  A4I  #$1
L0C06:  STAP                        ;store to OBJ_PTR
L0C07:  WS   OBJ_PTR                ;I = the address in OBJ_PTR
L0C08:  LDAP                        ;[OBJ_PTR]
L0C09:  STA  OBJ_Y
L0C0A:  LDA  OBJ_PTR
L0C0B:  A4I  #$1
L0C0C:  STAP                        ;store to OBJ_PTR
L0C0D:  WS   OBJ_PTR                ;I = the address in OBJ_PTR
L0C0E:  LDAP                        ;[OBJ_PTR]
L0C0F:  STA  OBJ_Z
L0C10:  LDA  OBJ_PTR
L0C11:  A4I  #$1
L0C12:  STAP                        ;store to OBJ_PTR
L0C13:  WS   OBJ_PTR                ;I = the address in OBJ_PTR
L0C14:  LDAP                        ;[OBJ_PTR]
L0C15:  STA  TMP13                  ;the headings,
L0C16:  LDA  OBJ_PTR
L0C17:  A4I  #$1
L0C18:  STAP                        ;store to OBJ_PTR
L0C19:  WS   OBJ_PTR                ;I = the address in OBJ_PTR
L0C1A:  LDAP                        ;[OBJ_PTR]
L0C1B:  STA  TMP14
L0C1C:  LDA  OBJ_PTR
L0C1D:  A4I  #$1
L0C1E:  STAP                        ;store to OBJ_PTR
L0C1F:  WS   OBJ_PTR                ;I = the address in OBJ_PTR
L0C20:  LDAP                        ;[OBJ_PTR]
L0C21:  STA  TMP15                  ;the speed,
L0C22:  LDA  OBJ_PTR
L0C23:  A4I  #$2
L0C24:  STAP                        ;store to OBJ_PTR
L0C25:  WS   OBJ_PTR                ;I = the address in OBJ_PTR
L0C26:  LDAP                        ;[OBJ_PTR]
L0C27:  STA  TMP1A                  ;the destination x
L0C28:  SUB  OBJ_X
L0C29:  ASR
L0C2A:  ASR
L0C2B:  ASR
L0C2C:  ASR
L0C2D:  STA  TMP16                  ;steering x = (destination - x) / 16,
L0C2E:  LDAI #$000
L0C2F:  A8I  #$1E
L0C31:  TST  TMP16
L0C32:  LPAI L0C48
L0C34:  JLT                         ;clamped to -$1E..$1E  if TMP16 < $1E -> L0C48
L0C35:  LDAI #$800
L0C36:  TST  TMP16
L0C37:  LPAI L0C44
L0C39:  JLT                         ;if TMP16 < $800 -> L0C44
L0C3A:  LDAI #$000
L0C3B:  S8I  #$1E
L0C3D:  TST  TMP16
L0C3E:  LPAI L0C47
L0C40:  JLT                         ;if TMP16 < $FE2 -> L0C47
L0C41:  LPAI L0C48
L0C43:  JMP

L0C44:  LDAI #$000
L0C45:  A8I  #$1E
L0C47:  STA  TMP16
L0C48:  LDA  OBJ_PTR
L0C49:  A4I  #$1
L0C4A:  STAP                        ;store to OBJ_PTR
L0C4B:  WS   OBJ_PTR                ;I = the address in OBJ_PTR
L0C4C:  LDAP                        ;[OBJ_PTR]
L0C4D:  STA  TMP1B
L0C4E:  SUB  OBJ_Y
L0C4F:  ASR
L0C50:  ASR
L0C51:  ASR
L0C52:  ASR
L0C53:  STA  TMP17                  ;steering y the same way
L0C54:  LDAI #$000
L0C55:  A8I  #$1E
L0C57:  TST  TMP17
L0C58:  LPAI L0C6E
L0C5A:  JLT                         ;if TMP17 < $1E -> L0C6E
L0C5B:  LDAI #$800
L0C5C:  TST  TMP17
L0C5D:  LPAI L0C6A
L0C5F:  JLT                         ;if TMP17 < $800 -> L0C6A
L0C60:  LDAI #$000
L0C61:  S8I  #$1E
L0C63:  TST  TMP17
L0C64:  LPAI L0C6D
L0C66:  JLT                         ;if TMP17 < $FE2 -> L0C6D
L0C67:  LPAI L0C6E
L0C69:  JMP

L0C6A:  LDAI #$000
L0C6B:  A8I  #$1E
L0C6D:  STA  TMP17
L0C6E:  LDA  OBJ_PTR
L0C6F:  A4I  #$1
L0C70:  STAP                        ;store to OBJ_PTR
L0C71:  WS   OBJ_PTR                ;I = the address in OBJ_PTR
L0C72:  LDAP                        ;[OBJ_PTR]
L0C73:  TST  OBJ_Z
L0C74:  LPAI L0C81
L0C76:  JCZ                         ;not past the destination depth  if [OBJ_PTR] < OBJ_Z -> L0C81
L0C77:  LDAI #$000
L0C78:  A8I  #$40
L0C7A:  SUB  TMP16
L0C7B:  STAP                        ;past it: turn round ($40 = half a turn)  store to TMP16
L0C7C:  LDAI #$000
L0C7D:  A8I  #$40
L0C7F:  SUB  TMP17
L0C80:  STAP                        ;store to TMP17
L0C81:  LDA  OBJ_PTR
L0C82:  S4I  #$6
L0C83:  STAP                        ;back to FTRn_HEADX  store to OBJ_PTR
L0C84:  LDA  TMP16
L0C85:  SUB  TMP13
L0C86:  STA  TMP1E                  ;how far to turn, mod a full turn
L0C87:  LDAI #$000
L0C88:  A8I  #$7F
L0C8A:  ANDP                        ;TMP1E
L0C8B:  STAP                        ;store to TMP1E
L0C8C:  LDAI #$000
L0C8D:  TST  TMP1E
L0C8E:  LPAI L0C9E
L0C90:  JEQ                         ;if TMP1E = 0 -> L0C9E
L0C91:  A8I  #$40
L0C93:  TST  TMP1E
L0C94:  LPAI L0C9C
L0C96:  JLT                         ;less than half a turn: + 1  if TMP1E < $40 -> L0C9C
L0C97:  LDAI #$000
L0C98:  S4I  #$1                    ;else - 1
L0C99:  LPAI L0C9E
L0C9B:  JMP

L0C9C:  LDAI #$000
L0C9D:  A4I  #$1
L0C9E:  ADD  TMP13
L0C9F:  STA  TMP1E                  ;SINCOS0: angle
L0CA0:  WS   OBJ_PTR                ;I = the address in OBJ_PTR
L0CA1:  STAP                        ;the new heading  store to [OBJ_PTR]
L0CA2:  LDAI #$C00
L0CA3:  A8I  #$A9
L0CA5:  STA  RET1                   ;SINCOS0: return address
L0CA6:  LPAI SINCOS0
L0CA8:  JMP                         ;call; returns to L0CA9

L0CA9:  LDA  TMP1A                  ;sine / cosine of HEADX kept in TMP1C / TMP1D
L0CAA:  STA  TMP1C
L0CAB:  LDA  TMP1B
L0CAC:  STA  TMP1D
L0CAD:  LDA  OBJ_PTR
L0CAE:  A4I  #$1
L0CAF:  STAP                        ;store to OBJ_PTR
L0CB0:  LDA  TMP17
L0CB1:  SUB  TMP14
L0CB2:  STA  TMP1E
L0CB3:  LDAI #$000
L0CB4:  A8I  #$7F
L0CB6:  ANDP                        ;TMP1E
L0CB7:  STAP                        ;store to TMP1E
L0CB8:  LDAI #$000
L0CB9:  TST  TMP1E
L0CBA:  LPAI L0CCA
L0CBC:  JEQ                         ;if TMP1E = 0 -> L0CCA
L0CBD:  A8I  #$40
L0CBF:  TST  TMP1E
L0CC0:  LPAI L0CC8
L0CC2:  JLT                         ;if TMP1E < $40 -> L0CC8
L0CC3:  LDAI #$000
L0CC4:  S4I  #$1
L0CC5:  LPAI L0CCA
L0CC7:  JMP

L0CC8:  LDAI #$000
L0CC9:  A4I  #$1
L0CCA:  ADD  TMP14
L0CCB:  STA  TMP1E                  ;SINCOS0: angle
L0CCC:  WS   OBJ_PTR                ;I = the address in OBJ_PTR
L0CCD:  STAP                        ;the new y heading; SINCOS0 leaves its sine / cosine in TMP1A / TMP1B  store to [OBJ_PTR]
L0CCE:  LDAI #$C00
L0CCF:  A8I  #$D5
L0CD1:  STA  RET1                   ;SINCOS0: return address
L0CD2:  LPAI SINCOS0
L0CD4:  JMP                         ;call; returns to L0CD5

L0CD5:  SSA
L0CD6:  LDAI B,#$000
L0CD7:  LDAI #$800
L0CD8:  LDA  TMP1C
L0CD9:  LPAI L0CDE
L0CDB:  JLT                         ;if TMP1C < $800 -> L0CDE
L0CDC:  LDAI #$000
L0CDD:  SUBP                        ;TMP1C
L0CDE:  TST  TMP1B
L0CDF:  MUL
L0CE0:  MUL
L0CE1:  MUL
L0CE2:  MUL
L0CE3:  MUL
L0CE4:  MUL
L0CE5:  MUL
L0CE6:  MUL
L0CE7:  MUL
L0CE8:  LDAI #$800
L0CE9:  TST  TMP1C
L0CEA:  SSA
L0CEB:  STA  B,TMP13                ;|sin hx| x cos hy (9 MUL steps)
L0CEC:  LPAI L0CF2
L0CEE:  JLT                         ;if TMP1C < $800 -> L0CF2
L0CEF:  LDAI #$000
L0CF0:  SUB  TMP13
L0CF1:  STAP                        ;with the sign of sin hx  store to TMP13
L0CF2:  SSA
L0CF3:  LDAI B,#$000
L0CF4:  LDAI #$800
L0CF5:  LDA  TMP13
L0CF6:  LPAI L0CFB
L0CF8:  JLT                         ;if TMP13 < $800 -> L0CFB
L0CF9:  LDAI #$000
L0CFA:  SUBP                        ;TMP13
L0CFB:  TST  TMP15
L0CFC:  MUL
L0CFD:  MUL
L0CFE:  MUL
L0CFF:  MUL
L0D00:  MUL
L0D01:  MUL
L0D02:  MUL
L0D03:  MUL
L0D04:  MUL
L0D05:  LDAI #$800
L0D06:  TST  TMP13
L0D07:  SSA
L0D08:  STA  B,TMP13                ;x the speed: dx
L0D09:  LPAI L0D0F
L0D0B:  JLT                         ;if TMP13 < $800 -> L0D0F
L0D0C:  LDAI #$000
L0D0D:  SUB  TMP13
L0D0E:  STAP                        ;store to TMP13
L0D0F:  SSA
L0D10:  LDAI B,#$000
L0D11:  LDAI #$800
L0D12:  LDA  TMP1A
L0D13:  LPAI L0D18
L0D15:  JLT                         ;if TMP1A < $800 -> L0D18
L0D16:  LDAI #$000
L0D17:  SUBP                        ;TMP1A
L0D18:  TST  TMP15
L0D19:  MUL
L0D1A:  MUL
L0D1B:  MUL
L0D1C:  MUL
L0D1D:  MUL
L0D1E:  MUL
L0D1F:  MUL
L0D20:  MUL
L0D21:  MUL
L0D22:  LDAI #$800
L0D23:  TST  TMP1A
L0D24:  SSA
L0D25:  STA  B,TMP14                ;|sin hy| x the speed: dy
L0D26:  LPAI L0D2C
L0D28:  JLT                         ;if TMP1A < $800 -> L0D2C
L0D29:  LDAI #$000
L0D2A:  SUB  TMP14
L0D2B:  STAP                        ;store to TMP14
L0D2C:  SSA
L0D2D:  LDAI B,#$000
L0D2E:  LDAI #$800
L0D2F:  LDA  TMP1D
L0D30:  LPAI L0D35
L0D32:  JLT                         ;if TMP1D < $800 -> L0D35
L0D33:  LDAI #$000
L0D34:  SUBP                        ;TMP1D
L0D35:  TST  TMP1B
L0D36:  MUL
L0D37:  MUL
L0D38:  MUL
L0D39:  MUL
L0D3A:  MUL
L0D3B:  MUL
L0D3C:  MUL
L0D3D:  MUL
L0D3E:  MUL
L0D3F:  LDAI #$800
L0D40:  TST  TMP1D
L0D41:  SSA
L0D42:  STA  B,RET1                 ;cos hx x cos hy
L0D43:  LPAI L0D49
L0D45:  JLT                         ;if TMP1D < $800 -> L0D49
L0D46:  LDAI #$000
L0D47:  SUB  RET1
L0D48:  STAP                        ;store to RET1
L0D49:  SSA
L0D4A:  LDAI B,#$000
L0D4B:  LDAI #$800
L0D4C:  LDA  RET1
L0D4D:  LPAI L0D52
L0D4F:  JLT                         ;if RET1 < $800 -> L0D52
L0D50:  LDAI #$000
L0D51:  SUBP                        ;RET1
L0D52:  TST  TMP15
L0D53:  MUL
L0D54:  MUL
L0D55:  MUL
L0D56:  MUL
L0D57:  MUL
L0D58:  MUL
L0D59:  MUL
L0D5A:  MUL
L0D5B:  MUL
L0D5C:  LDAI #$800
L0D5D:  TST  RET1
L0D5E:  SSA
L0D5F:  STA  B,TMP15                ;x the speed: dz
L0D60:  LPAI L0D66
L0D62:  JLT                         ;if RET1 < $800 -> L0D66
L0D63:  LDAI #$000
L0D64:  SUB  TMP15
L0D65:  STAP                        ;store to TMP15
L0D66:  LDA  OBJ_PTR
L0D67:  S4I  #$4
L0D68:  STAP                        ;back to FTRn_X  store to OBJ_PTR
L0D69:  LDA  TMP13
L0D6A:  WS   OBJ_PTR                ;I = the address in OBJ_PTR
L0D6B:  ADDP                        ;[OBJ_PTR]
L0D6C:  STAP                        ;x += dx  store to [OBJ_PTR]
L0D6D:  STA  OBJ_X
L0D6E:  LDA  OBJ_PTR
L0D6F:  A4I  #$1
L0D70:  STAP                        ;store to OBJ_PTR
L0D71:  LDA  TMP14
L0D72:  WS   OBJ_PTR                ;I = the address in OBJ_PTR
L0D73:  ADDP                        ;[OBJ_PTR]
L0D74:  STAP                        ;y += dy  store to [OBJ_PTR]
L0D75:  STA  OBJ_Y
L0D76:  LDA  OBJ_PTR
L0D77:  A4I  #$1
L0D78:  STAP                        ;store to OBJ_PTR
L0D79:  LDAI #$000
L0D7A:  SUB  TMP15
L0D7B:  WS   OBJ_PTR                ;I = the address in OBJ_PTR
L0D7C:  ADDP                        ;[OBJ_PTR]
L0D7D:  STAP                        ;z -= dz: toward the player  store to [OBJ_PTR]
L0D7E:  STA  OBJ_Z
L0D7F:  LDA  OBJ_PTR
L0D80:  A4I  #$9
L0D81:  STAP                        ;on to FTRn_SCRY  store to OBJ_PTR
L0D82:  SETP $1
L0D83:  LDA  OBJ_Z
L0D84:  SHR                         ;the depth for the divide: z / 2
L0D85:  SETP $0
L0D86:  STA  TMP09
L0D87:  SETP $1
L0D88:  LDA  OBJ_X
L0D89:  SETP $0
L0D8A:  STA  TMP05
L0D8B:  SETP $1
L0D8C:  LDA  OBJ_Y
L0D8D:  SETP $0
L0D8E:  STA  TMP06
L0D8F:  LDAI #$200
L0D90:  STA  TMP0D                  ;$200 / depth:
L0D91:  LDAI #$000
L0D92:  STA  TMP04

;------------------------------------------------------------------------------
; PROJDIV - Perspective: the reciprocal $200 / depth (depth in TMP09). The
;   whole part by repeated subtraction into TMP04, then 11 shift-and-subtract
;   steps for the fraction, left in TMP09.
;------------------------------------------------------------------------------
PROJDIV:
L0D93:  LDA  TMP0D
L0D94:  TST  TMP09
L0D95:  LPAI L0E03
L0D97:  JLT                         ;while the remainder is at least the depth  if TMP09 < TMP0D -> L0E03
L0D98:  SSA
L0D99:  LDAI B,#$000
L0D9A:  SHLB
L0D9B:  SSA
L0D9C:  A4I  B,#$1
L0D9D:  SUBP                        ;TMP09
L0D9E:  LPAI L0DA4
L0DA0:  JLT                         ;if TMP09 < A -> L0DA4
L0DA1:  ADDP                        ;TMP09
L0DA2:  SSA
L0DA3:  S4I  B,#$1
L0DA4:  SHLB
L0DA5:  SSA
L0DA6:  A4I  B,#$1
L0DA7:  SUBP
L0DA8:  LPAI L0DAE
L0DAA:  JLT                         ;if ? < A -> L0DAE
L0DAB:  ADDP
L0DAC:  SSA
L0DAD:  S4I  B,#$1
L0DAE:  SHLB
L0DAF:  SSA
L0DB0:  A4I  B,#$1
L0DB1:  SUBP
L0DB2:  LPAI L0DB8
L0DB4:  JLT                         ;if ? < A -> L0DB8
L0DB5:  ADDP
L0DB6:  SSA
L0DB7:  S4I  B,#$1
L0DB8:  SHLB
L0DB9:  SSA
L0DBA:  A4I  B,#$1
L0DBB:  SUBP
L0DBC:  LPAI L0DC2
L0DBE:  JLT                         ;if ? < A -> L0DC2
L0DBF:  ADDP
L0DC0:  SSA
L0DC1:  S4I  B,#$1
L0DC2:  SHLB
L0DC3:  SSA
L0DC4:  A4I  B,#$1
L0DC5:  SUBP
L0DC6:  LPAI L0DCC
L0DC8:  JLT                         ;if ? < A -> L0DCC
L0DC9:  ADDP
L0DCA:  SSA
L0DCB:  S4I  B,#$1
L0DCC:  SHLB
L0DCD:  SSA
L0DCE:  A4I  B,#$1
L0DCF:  SUBP
L0DD0:  LPAI L0DD6
L0DD2:  JLT                         ;if ? < A -> L0DD6
L0DD3:  ADDP
L0DD4:  SSA
L0DD5:  S4I  B,#$1
L0DD6:  SHLB
L0DD7:  SSA
L0DD8:  A4I  B,#$1
L0DD9:  SUBP
L0DDA:  LPAI L0DE0
L0DDC:  JLT                         ;if ? < A -> L0DE0
L0DDD:  ADDP
L0DDE:  SSA
L0DDF:  S4I  B,#$1
L0DE0:  SHLB
L0DE1:  SSA
L0DE2:  A4I  B,#$1
L0DE3:  SUBP
L0DE4:  LPAI L0DEA
L0DE6:  JLT                         ;if ? < A -> L0DEA
L0DE7:  ADDP
L0DE8:  SSA
L0DE9:  S4I  B,#$1
L0DEA:  SHLB
L0DEB:  SSA
L0DEC:  A4I  B,#$1
L0DED:  SUBP
L0DEE:  LPAI L0DF4
L0DF0:  JLT                         ;if ? < A -> L0DF4
L0DF1:  ADDP
L0DF2:  SSA
L0DF3:  S4I  B,#$1
L0DF4:  SHLB
L0DF5:  SSA
L0DF6:  A4I  B,#$1
L0DF7:  SUBP
L0DF8:  LPAI L0DFE
L0DFA:  JLT                         ;if ? < A -> L0DFE
L0DFB:  ADDP
L0DFC:  SSA
L0DFD:  S4I  B,#$1
L0DFE:  SSA
L0DFF:  STA  B,TMP09                ;the fraction
L0E00:  LPAI PROJECT
L0E02:  JMP

L0E03:  SUBP
L0E04:  STA  TMP0D                  ;subtract, and count the whole part
L0E05:  LDA  TMP04
L0E06:  A4I  #$1
L0E07:  STAP                        ;store to TMP04
L0E08:  LPAI PROJDIV
L0E0A:  JMP


;------------------------------------------------------------------------------
; PROJECT - Screen position: x and y (TMP05 / TMP06) times the reciprocal - the
;   fraction with MUL steps into TMP07 / TMP08, then the whole part (TMP04) by
;   adding the coordinate that many times.
;------------------------------------------------------------------------------
PROJECT:
L0E0B:  SSA
L0E0C:  LDAI B,#$000
L0E0D:  LDAI #$800
L0E0E:  LDA  TMP05
L0E0F:  LPAI L0E14
L0E11:  JLT                         ;if TMP05 < $800 -> L0E14
L0E12:  LDAI #$000
L0E13:  SUBP                        ;TMP05
L0E14:  TST  TMP09
L0E15:  MUL
L0E16:  MUL
L0E17:  MUL
L0E18:  MUL
L0E19:  MUL
L0E1A:  MUL
L0E1B:  MUL
L0E1C:  MUL
L0E1D:  MUL
L0E1E:  MUL
L0E1F:  MUL
L0E20:  SSA
L0E21:  STA  B,TMP07                ;x times the fraction
L0E22:  LDAI #$800
L0E23:  TST  TMP05
L0E24:  LPAI L0E2A
L0E26:  JLT                         ;if TMP05 < $800 -> L0E2A
L0E27:  LDAI #$000
L0E28:  SUB  TMP07
L0E29:  STAP                        ;store to TMP07
L0E2A:  SSA
L0E2B:  LDAI B,#$000
L0E2C:  LDAI #$800
L0E2D:  LDA  TMP06
L0E2E:  LPAI L0E33
L0E30:  JLT                         ;if TMP06 < $800 -> L0E33
L0E31:  LDAI #$000
L0E32:  SUBP                        ;TMP06
L0E33:  TST  TMP09
L0E34:  MUL
L0E35:  MUL
L0E36:  MUL
L0E37:  MUL
L0E38:  MUL
L0E39:  MUL
L0E3A:  MUL
L0E3B:  MUL
L0E3C:  MUL
L0E3D:  MUL
L0E3E:  MUL
L0E3F:  SSA
L0E40:  STA  B,TMP08                ;y times the fraction
L0E41:  LDAI #$800
L0E42:  TST  TMP06
L0E43:  LPAI L0E49
L0E45:  JLT                         ;if TMP06 < $800 -> L0E49
L0E46:  LDAI #$000
L0E47:  SUB  TMP08
L0E48:  STAP                        ;store to TMP08
L0E49:  SSA
L0E4A:  LDAI B,#$000
L0E4B:  SSA
L0E4C:  SUB  B,TMP04                ;B = -the whole part: add x and y that many times
L0E4D:  LPAI L0E5B
L0E4F:  JEQ                         ;if TMP04 = 0 -> L0E5B
L0E50:  LPAI L0E52
L0E52:  LDA  TMP05
L0E53:  ADD  TMP07
L0E54:  STAP                        ;store to TMP07
L0E55:  LDA  TMP06
L0E56:  ADD  TMP08
L0E57:  STAP                        ;store to TMP08
L0E58:  SSA
L0E59:  A4I  B,#$1
L0E5A:  JCZ                         ;once per unit of the whole part  until B + 1 carries (reaches $1000) -> L0E52
L0E5B:  LDAI #$300
L0E5C:  SHR
L0E5D:  ADD  TMP08
L0E5E:  SETP $1
L0E5F:  WS   OBJ_PTR                ;I = the address in OBJ_PTR
L0E60:  STAP                        ;FTRn_SCRY = $180 + the screen y  store to [OBJ_PTR]
L0E61:  LDA  OBJ_PTR
L0E62:  S4I  #$1
L0E63:  STAP                        ;store to OBJ_PTR
L0E64:  LDAI #$200
L0E65:  SETP $0
L0E66:  ADD  TMP07
L0E67:  SETP $1
L0E68:  WS   OBJ_PTR                ;I = the address in OBJ_PTR
L0E69:  STAP                        ;FTRn_SCRX = $200 + the screen x  store to [OBJ_PTR]

;------------------------------------------------------------------------------
; HITTEST - Hit test, only in a shot's last three frames (SHOT 1-3, when the
;   beams reach the crosshair) and only for a fighter farther than z = $200: a
;   hit if its screen offset is within $16 + (-z >> 7) of the crosshair
;   (XHAIR_X / XHAIR_Y) in x and in y, a target that grows as the fighter comes
;   nearer.
;------------------------------------------------------------------------------
HITTEST:
L0E6A:  LDAI #$000
L0E6B:  SETP $6
L0E6C:  TST  SHOT
L0E6D:  LPAI FTRRET
L0E6F:  JEQ                         ;no shot  if SHOT = 0 -> FTRRET
L0E70:  A4I  #$3
L0E71:  TST  SHOT
L0E72:  JCZ                         ;the beams are not at the crosshair yet  if 3 < SHOT -> FTRRET
L0E73:  LDAI #$200
L0E74:  SETP $1
L0E75:  TST  OBJ_Z
L0E76:  JLT                         ;too close to hit  if OBJ_Z < $200 -> FTRRET
L0E77:  LDAI #$000
L0E78:  SUBP                        ;OBJ_Z
L0E79:  SHR
L0E7A:  SHR
L0E7B:  SHR
L0E7C:  SHR
L0E7D:  SHR
L0E7E:  SHR
L0E7F:  SHR
L0E80:  A8I  #$16                   ;the target size: $16 + (-z >> 7)
L0E82:  SETP $0
L0E83:  STA  TMP09
L0E84:  SETP $2
L0E85:  LDA  XHAIR_X
L0E86:  SETP $0
L0E87:  SUB  TMP07
L0E88:  STAP                        ;store to TMP07
L0E89:  LDAI #$800
L0E8A:  LDAP                        ;TMP07
L0E8B:  LPAI L0E90
L0E8D:  JLT                         ;if TMP07 < $800 -> L0E90
L0E8E:  LDAI #$000
L0E8F:  SUBP                        ;TMP07
L0E90:  SUB  TMP09
L0E91:  LPAI FTRRET
L0E93:  JLT                         ;too far off in x  if TMP09 < A -> FTRRET
L0E94:  SETP $2
L0E95:  LDA  XHAIR_Y
L0E96:  SETP $0
L0E97:  SUB  TMP08
L0E98:  STAP                        ;store to TMP08
L0E99:  LDAI #$800
L0E9A:  LDA  TMP08
L0E9B:  LPAI L0EA0
L0E9D:  JLT                         ;if TMP08 < $800 -> L0EA0
L0E9E:  LDAI #$000
L0E9F:  SUBP                        ;TMP08
L0EA0:  SUB  TMP09
L0EA1:  LPAI FTRRET
L0EA3:  JLT                         ;too far off in y  if TMP09 < A -> FTRRET
L0EA4:  SETP $1
L0EA5:  LDA  OBJ_PTR
L0EA6:  S4I  #$4                    ;back to FTRn_STATE
L0EA7:  STAP                        ;store to OBJ_PTR
L0EA8:  LDAI #$000
L0EA9:  A4I  #$3
L0EAA:  WS   OBJ_PTR                ;I = the address in OBJ_PTR
L0EAB:  STAP                        ;a hit: the explosion starts  store to [OBJ_PTR]

;------------------------------------------------------------------------------
; SCOREADD - Score a hit: the fighter starts exploding, HIT_POINTS are added to
;   the BCD score (units into SCORE_LO, the rest into SCORE_HI with its digits
;   adjusted), and the hit flash starts. The third hit of a wave (HITS = 3) is
;   scored twice.
;------------------------------------------------------------------------------
SCOREADD:
L0EAC:  LDAI #$000
L0EAD:  SETP $6
L0EAE:  STA  FIRE_NOW
L0EAF:  A4I  #$F
L0EB0:  SETP $7
L0EB1:  STA  HIT_FLASH              ;the hit flash
L0EB2:  SETP $2
L0EB3:  TST  HIT_POINTS
L0EB4:  ANDP                        ;units of HIT_POINTS  HIT_POINTS
L0EB5:  SETP $6
L0EB6:  ADD  SCORE_LO
L0EB7:  STAP                        ;into SCORE_LO  store to SCORE_LO
L0EB8:  S4I  #$A
L0EB9:  LPAI L0EC0
L0EBB:  JCZ                         ;below 10  if HIT_POINTS & $F + SCORE_LO < $A -> L0EC0
L0EBC:  STAP                        ;else - 10, and carry 1  store to SCORE_LO
L0EBD:  LDAI #$000
L0EBE:  A4I  #$1
L0EBF:  STA  FIRE_NOW
L0EC0:  SETP $2
L0EC1:  LDA  HIT_POINTS
L0EC2:  SHR
L0EC3:  SHR
L0EC4:  SHR
L0EC5:  SHR
L0EC6:  SETP $6
L0EC7:  ADD  FIRE_NOW
L0EC8:  ADD  SCORE_HI               ;the rest of HIT_POINTS and the carry into SCORE_HI
L0EC9:  STAP                        ;store to SCORE_HI
L0ECA:  LDAI #$000
L0ECB:  A4I  #$F
L0ECC:  ANDP                        ;SCORE_HI
L0ECD:  S4I  #$A
L0ECE:  LPAI L0EDF
L0ED0:  JCZ                         ;units digit below 10  if SCORE_HI & $F < $A -> L0EDF
L0ED1:  LDAP                        ;SCORE_HI
L0ED2:  A4I  #$6                    ;else + 6: decimal adjust
L0ED3:  STAP                        ;store to SCORE_HI
L0ED4:  LDAI #$000
L0ED5:  A8I  #$F0
L0ED7:  ANDP                        ;SCORE_HI
L0ED8:  S8I  #$A0
L0EDA:  JCZ                         ;tens digit below 10  if SCORE_HI & $F0 < $A0 -> L0EDF
L0EDB:  LDAP                        ;SCORE_HI
L0EDC:  A8I  #$60                   ;else + $60
L0EDE:  STAP                        ;store to SCORE_HI
L0EDF:  SETP $2
L0EE0:  LDA  HITS
L0EE1:  A4I  #$1
L0EE2:  STAP                        ;one more hit this wave  store to HITS
L0EE3:  S4I  #$3
L0EE4:  LPAI SCOREADD
L0EE6:  JEQ                         ;the third: score it again  if HITS+1 = 3 -> SCOREADD
FTRRET:
L0EE7:  SETP $0
L0EE8:  TST  RET0
L0EE9:  LPAP                        ;J = the address in RET0
L0EEA:  JMP                         ;J from RAM -> XHAIRDRAW, LASERL, LASERR


;------------------------------------------------------------------------------
; SINCOS0 - Sine of the angle in TMP1E (0-$7F a full turn, cut to 7 bits here)
;   into TMP1A and its cosine into TMP1B, both x 255 and signed, from the
;   quarter-wave table SINTAB0 by quadrant (below $20 the cosine is SINTAB0[$20
;   - angle]). Returns through RET1. (Bank 1 has its own copy, SINCOS1.)
;   Called from L0CA8, L0CD4.
;------------------------------------------------------------------------------
SINCOS0:
L0EEB:  LDAI #$000
L0EEC:  A8I  #$7F
L0EEE:  TST  TMP1E
L0EEF:  ANDP                        ;TMP1E
L0EF0:  STAP                        ;the angle, cut to 7 bits  store to TMP1E
L0EF1:  LDAI #$F00
L0EF2:  A8I  #$6C
L0EF4:  STA  TMP1A                  ;TMP1A = the table's end, SINTAB0 + $20
L0EF5:  LDAI #$000
L0EF6:  A8I  #$20
L0EF8:  TST  TMP1E
L0EF9:  LPAI L0F15
L0EFB:  JLT                         ;below $20: the first quadrant  if TMP1E < $20 -> L0F15
L0EFC:  SHL
L0EFD:  TST  TMP1E
L0EFE:  LPAI L0F21
L0F00:  JLT                         ;below $40: the second  if TMP1E < A -> L0F21
L0F01:  A8I  #$20
L0F03:  TST  TMP1E
L0F04:  LPAI L0F35
L0F06:  JLT                         ;below $60: the third; else the fourth  if TMP1E < A -> L0F35
L0F07:  LDA  TMP1A
L0F08:  ADD  TMP1E
L0F09:  S8I  #$80
L0F0B:  LKP                         ;table read $0F4C-$0F6B
L0F0D:  STA  TMP1B
L0F0E:  LDA  TMP1A
L0F0F:  A8I  #$60
L0F11:  SUB  TMP1E
L0F12:  LPAI L0F43
L0F14:  JMP

L0F15:  LDA  TMP1A
L0F16:  SUB  TMP1E
L0F17:  LKP                         ;cosine = SINTAB0[$20 - angle]  table read $0F4D-$0F6C
L0F19:  STA  TMP1B
L0F1A:  LDAI #$F00
L0F1B:  A8I  #$4C
L0F1D:  ADD  TMP1E                  ;SINTAB0 + angle: the sine, read at L0F2F
L0F1E:  LPAI L0F2F
L0F20:  JMP

L0F21:  LDA  TMP1A
L0F22:  ADD  TMP1E
L0F23:  S8I  #$40
L0F25:  LKP                         ;table read $0F4C-$0F5C
L0F27:  STA  TMP1B
L0F28:  LDAI #$000
L0F29:  SUBP                        ;TMP1B
L0F2A:  STAP                        ;store to TMP1B
L0F2B:  LDA  TMP1A
L0F2C:  A8I  #$20
L0F2E:  SUB  TMP1E
L0F2F:  LKP                         ;table read $0F4C-$0F6C
L0F31:  STA  TMP1A
L0F32:  LPAI L0F49
L0F34:  JMP

L0F35:  LDA  TMP1A
L0F36:  A8I  #$40
L0F38:  SUB  TMP1E
L0F39:  LKP                         ;table read $0F4D-$0F5A
L0F3B:  STA  TMP1B
L0F3C:  LDAI #$000
L0F3D:  SUBP                        ;TMP1B
L0F3E:  STAP                        ;store to TMP1B
L0F3F:  LDA  TMP1A
L0F40:  ADD  TMP1E
L0F41:  S8I  #$60
L0F43:  LKP                         ;table read $0F4D-$0F6C
L0F45:  STA  TMP1A
L0F46:  LDAI #$000
L0F47:  SUBP                        ;TMP1A
L0F48:  STAP                        ;store to TMP1A
L0F49:  TST  RET1
L0F4A:  LPAP                        ;back to the caller  J = the address in RET1
L0F4B:  JMP                         ;J from RAM -> L0CA9, L0CD5

;$0F4C-$0FFF, read by LKP at L0F0B, L0F17, L0F25, L0F2F, L0F39, L0F43
SINTAB0:
L0F4C:  .byte $00, $0D, $19, $25, $32, $3E, $4A, $56  ;sine x 255, entries 0-7 (32 = a quarter turn)
L0F54:  .byte $62, $6D, $78, $83, $8E, $98, $A2, $AB  ;sine x 255, entries 8-15 (32 = a quarter turn)
L0F5C:  .byte $B4, $BD, $C5, $CD, $D4, $DB, $E1, $E7  ;sine x 255, entries 16-23 (32 = a quarter turn)
L0F64:  .byte $EC, $F0, $F4, $F7, $FA, $FC, $FE, $FF  ;sine x 255, entries 24-31 (32 = a quarter turn)
L0F6C:  .byte $FF                   ;sine x 255, entry 32: sin 90 degrees
DEVJUNK1:
L0F6D:  .byte $E2, $FF, $E0, $07, $3A, $CB, $1C, $FE
L0F75:  .byte $FF, $C2, $7F, $18, $01, $CD, $03, $CD
L0F7D:  .byte $AE, $08, $01, $B5, $1D, $CD, $2B, $15
L0F85:  .byte $01, $47, $1C, $CD, $12, $08, $01, $47
L0F8D:  .byte $1C, $C5, $1E, $10, $01, $57, $1C, $CD
L0F95:  .byte $06, $09, $01, $EB, $03, $CD, $2B, $15
L0F9D:  .byte $01, $47, $1C, $CD, $55, $08, $C9, $0E
L0FA5:  .byte $07, $21, $1F, $1C, $CD, $A9, $1B, $3E
L0FAD:  .byte $FF, $CD, $80, $1B, $2B, $EB, $21, $1B
L0FB5:  .byte $00, $20, $90, $00, $40, $00, $08, $21
L0FBD:  .byte $10, $92, $10, $21, $12, $42, $48, $00
L0FC5:  .byte $09, $10, $02, $40, $00, $10, $40, $08
L0FCD:  .byte $08, $41, $02, $00, $82, $42, $48, $09
L0FD5:  .byte $09, $20, $42, $21, $01, $20, $08, $22
L0FDD:  .byte $12, $11, $10, $10, $88, $42, $48, $49
L0FE5:  .byte $24, $24, $92, $42, $49, $24, $42, $49
L0FED:  .byte $20, $84, $24, $84, $10, $92, $09, $10
L0FF5:  .byte $92, $48, $49, $09, $20, $82, $44, $04
L0FFD:  .byte $24, $90, $90

;==============================================================================
; BANK 1   $1000-$1FFF   tgunner.t71 (even bytes) + tgunner.p71 (odd bytes)
;==============================================================================


;------------------------------------------------------------------------------
; TESTMODE - Test pattern, reached at power-on with START held: turns every
;   sound off, then each frame draws the figure TESTFIG (crossed lines, a
;   square and a triangle; a capture is in README.md) for adjusting the
;   monitor. Only a reset leaves it.
;------------------------------------------------------------------------------
TESTMODE:
L1000:  NOP
L1001:  NOP
L1002:  LPAI TESTSNDOFF             ;every sound off first (TESTSNDOFF comes back to $1005)
L1004:  JMP


;------------------------------------------------------------------------------
; TESTLOOP - Test pattern loop: wait for the frame, clear the watchdog, centre
;   the beam and draw TESTFIG with DRAWMODEL3D, which returns here.
;   Reached by the jump through RAM at L147C.
;------------------------------------------------------------------------------
TESTLOOP:
L1005:  FRM                         ;wait for the frame
L1006:  FRM                         ;repeated FRM: fetched and skipped, no second wait
L1007:  LDAI #$000
L1008:  OUT  OUT_INTENSITY          ;dim
L1009:  SETP $1
L100A:  STA  OBJ_X
L100B:  STA  OBJ_Y
L100C:  CST                         ;CST: clear the watchdog  OBJ_Y
L100D:  SSA
L100E:  LDAI B,#$300
L100F:  SHRB
L1010:  LDAI #$200
L1011:  IV                          ;beam to the centre
L1012:  LDAI #$000
L1013:  S8I  #$38
L1015:  A4I  #$1
L1016:  LPAI L1015
L1018:  JCZ                         ;count up to 0 (a delay of $38 loops) -> L1015
L1019:  LDAI #$100
L101A:  STA  OBJ_Z                  ;z = $100  DRAWMODEL3D: z
L101B:  LDAI #$000
L101C:  STA  TMP1C                  ;DRAWMODEL3D: sine of angle 1
L101D:  STA  TMP1A                  ;no turn: sine 0, cosine $FF  DRAWMODEL3D: sine of angle 2
L101E:  A8I  #$FF
L1020:  STA  TMP1D                  ;DRAWMODEL3D: cosine of angle 1
L1021:  STA  TMP1B                  ;DRAWMODEL3D: cosine of angle 2
L1022:  LDAI #$000
L1023:  A8I  #$31
L1025:  STA  TMP16                  ;vertex list $1031  DRAWMODEL3D: vertex list
L1026:  A8I  #$2E
L1028:  STA  TMP17                  ;edge list $1031 + $2E = $105F  DRAWMODEL3D: edge list
L1029:  LDAI #$000
L102A:  A8I  #$05
L102C:  SETP $2
L102D:  STA  RET2                   ;DRAWMODEL3D returns to $1005: round again  DRAWMODEL3D: return address
L102E:  LPAI DRAWMODEL3D
L1030:  JMP

;$1031-$1071, read by LKP at L113E, L114B, L1154, L139E, L16A7, L16B5 ...
TESTFIG:
L1031:  .byte $80, $DC, $80         ;vertex  0: x   +0  y  +92  z   +0
L1034:  .byte $80, $80, $80         ;vertex  1: x   +0  y   +0  z   +0
L1037:  .byte $78, $78, $80         ;vertex  2: x   -8  y   -8  z   +0
L103A:  .byte $08, $78, $80         ;vertex  3: x -120  y   -8  z   +0
L103D:  .byte $04, $80, $80         ;vertex  4: x -124  y   +0  z   +0
L1040:  .byte $78, $28, $80         ;vertex  5: x   -8  y  -88  z   +0
L1043:  .byte $80, $24, $80         ;vertex  6: x   +0  y  -92  z   +0
L1046:  .byte $88, $78, $80         ;vertex  7: x   +8  y   -8  z   +0
L1049:  .byte $F8, $78, $80         ;vertex  8: x +120  y   -8  z   +0
L104C:  .byte $FC, $80, $80         ;vertex  9: x +124  y   +0  z   +0
L104F:  .byte $A0, $60, $80         ;vertex 10: x  +32  y  -32  z   +0
L1052:  .byte $A8, $58, $80         ;vertex 11: x  +40  y  -40  z   +0
L1055:  .byte $A8, $A8, $80         ;vertex 12: x  +40  y  +40  z   +0
L1058:  .byte $58, $A8, $80         ;vertex 13: x  -40  y  +40  z   +0
L105B:  .byte $58, $58, $80         ;vertex 14: x  -40  y  -40  z   +0
L105E:  .byte $FF                   ;end of vertices
TESTFIG_EDGES:
L105F:  .byte $23, $41, $25, $61, $78, $91, $7A, $BC  ;edges 2-3 4-1 2-5 6-1 7-8 9-1 7-10 11-12
L1067:  .byte $CD, $D0, $01, $1D, $DE, $EB  ;edges 12-13 13-0 0-1 1-13 13-14 14-11
L106D:  .byte $FF                   ;end of edges
L106E:  .byte $E2, $FF, $D6, $30
NEXTOBJ:
L1072:  LDAP
L1073:  LDAI #$000
L1074:  OUT  OUT_INTENSITY          ;flying (FTRn_STATE 0)  dim
L1075:  LPAI DRAWMODEL3D
L1077:  JEQ                         ;if A = 0 -> DRAWMODEL3D
L1078:  A4I  #$1
L1079:  OUT  OUT_INTENSITY          ;exploding  bright
L107A:  JMP

L107B:  .byte $18, $05, $CD, $98, $06  ;$107B-$107F, not read in the traces

;------------------------------------------------------------------------------
; DRAWFTRS - Bank 1 entry of the frame: draw each live fighter's 3D model
;   (DRAWMODEL), then return through RET0 to bank 1's HUD (DRAWHUD) or the
;   title.
;------------------------------------------------------------------------------
DRAWFTRS:
L1080:  NOP
L1081:  LDAI #$000
L1082:  SETP $3
L1083:  TST  FTR1_MODEL
L1084:  LPAI L1094
L1086:  JEQ                         ;if FTR1_MODEL = 0 -> L1094
L1087:  LDAI #$000
L1088:  A8I  #$3B
L108A:  SETP $1
L108B:  STA  OBJ_PTR                ;DRAWMODEL: the fighter (address of FTRn_SCRX)
L108C:  LDAI #$000
L108D:  A8I  #$94
L108F:  SETP $2
L1090:  STA  RET2                   ;DRAWMODEL: return address  return address: L1094
L1091:  LPAI DRAWMODEL
L1093:  JMP                         ;call; returns to L1094 via RET2

L1094:  LDAI #$000
L1095:  SETP $4
L1096:  TST  FTR2_MODEL
L1097:  LPAI L10A7
L1099:  JEQ                         ;if FTR2_MODEL = 0 -> L10A7
L109A:  LDAI #$000
L109B:  A8I  #$4B
L109D:  SETP $1
L109E:  STA  OBJ_PTR                ;DRAWMODEL: the fighter (address of FTRn_SCRX)
L109F:  LDAI #$000
L10A0:  A8I  #$A7
L10A2:  SETP $2
L10A3:  STA  RET2                   ;DRAWMODEL: return address  return address: L10A7
L10A4:  LPAI DRAWMODEL
L10A6:  JMP                         ;call; returns to L10A7 via RET2

L10A7:  LDAI #$000
L10A8:  SETP $5
L10A9:  TST  FTR3_MODEL
L10AA:  LPAI DRAWFTRSRET
L10AC:  JEQ                         ;if FTR3_MODEL = 0 -> DRAWFTRSRET
L10AD:  LDAI #$000
L10AE:  A8I  #$5B
L10B0:  SETP $1
L10B1:  STA  OBJ_PTR
L10B2:  LDAI #$400
L10B3:  A8I  #$7D
L10B5:  SETP $2
L10B6:  STA  RET2

;------------------------------------------------------------------------------
; DRAWMODEL - Draw one fighter. OBJ_PTR = its FTRn_SCRX: nothing is drawn if
;   the centre is off the screen; else the model (FTRn_MODEL: edge-list
;   pointer, then vertices) at FTRn_X/Y/Z, turned by two angles, FTRn_HEADX
;   (sine / cosine into TMP1C / TMP1D) and FTRn_HEADY (TMP1A / TMP1B), and
;   drawn by DRAWMODEL3D with OBJ_PTR = FTRn_STATE: dim while flying, bright
;   while exploding. Returns through RET2.
;   Called from L1093, L10A6 (return address in RET2).
;------------------------------------------------------------------------------
DRAWMODEL:
L10B7:  SETP $1
L10B8:  WS   OBJ_PTR                ;I = the address in OBJ_PTR
L10B9:  LDAP                        ;[OBJ_PTR]
L10BA:  SETP $2
L10BB:  STA  CTR_X                  ;the fighter's screen x + $200
L10BC:  SETP $1
L10BD:  STA  TMP13
L10BE:  LDAI #$400
L10BF:  TST  TMP13
L10C0:  LPAI MODELRET
L10C2:  JCZ                         ;off the screen: draw nothing  if $400 < TMP13 -> MODELRET
L10C3:  LDA  OBJ_PTR
L10C4:  A4I  #$1
L10C5:  STAP                        ;store to OBJ_PTR
L10C6:  WS   OBJ_PTR                ;I = the address in OBJ_PTR
L10C7:  LDAP                        ;[OBJ_PTR]
L10C8:  SETP $2
L10C9:  STA  CTR_Y
L10CA:  SSA
L10CB:  LDAP B                      ;CTR_Y
L10CC:  LDAI #$300
L10CD:  TST  CTR_Y
L10CE:  JCZ                         ;off the screen  if $300 < CTR_Y -> MODELRET
L10CF:  SETP $1
L10D0:  LDA  TMP13
L10D1:  LPAI L10D3
L10D3:  JVN                         ;while the vector generator is busy -> L10D3
L10D4:  IV                          ;beam to the fighter's centre
L10D5:  LDA  OBJ_PTR
L10D6:  S4I  #$C
L10D7:  STAP                        ;back to FTRn_MODEL  store to OBJ_PTR
L10D8:  WS   OBJ_PTR                ;I = the address in OBJ_PTR
L10D9:  LDAP                        ;[OBJ_PTR]
L10DA:  STA  TMP17
L10DB:  A4I  #$2
L10DC:  STA  TMP16                  ;the vertices follow the 2-byte header
L10DD:  S4I  #$1
L10DE:  LKP                         ;table read $1482-$153A
L10E0:  STA  RET1
L10E1:  SSA
L10E2:  LDAP B                      ;RET1
L10E3:  LDA  TMP17
L10E4:  LKP                         ;table read $1481-$1539
L10E6:  STAP                        ;store to TMP17
L10E7:  LDAI #$000
L10E8:  SHRB
L10E9:  SHRB
L10EA:  SHRB
L10EB:  SHRB
L10EC:  ADDP                        ;TMP17
L10ED:  STAP                        ;TMP17 = the edge list: low byte + high nibble x $100  store to TMP17
L10EE:  LDA  OBJ_PTR
L10EF:  A4I  #$1
L10F0:  STAP                        ;store to OBJ_PTR
L10F1:  WS   OBJ_PTR                ;I = the address in OBJ_PTR
L10F2:  LDAP                        ;[OBJ_PTR]
L10F3:  STA  OBJ_X                  ;the position, FTRn_X / Y / Z
L10F4:  LDA  OBJ_PTR
L10F5:  A4I  #$1
L10F6:  STAP                        ;store to OBJ_PTR
L10F7:  WS   OBJ_PTR                ;I = the address in OBJ_PTR
L10F8:  LDAP                        ;[OBJ_PTR]
L10F9:  STA  OBJ_Y
L10FA:  LDA  OBJ_PTR
L10FB:  A4I  #$1
L10FC:  STAP                        ;store to OBJ_PTR
L10FD:  WS   OBJ_PTR                ;I = the address in OBJ_PTR
L10FE:  LDAP                        ;[OBJ_PTR]
L10FF:  STA  OBJ_Z
L1100:  LDA  OBJ_PTR
L1101:  A4I  #$1
L1102:  STAP                        ;store to OBJ_PTR
L1103:  WS   OBJ_PTR                ;I = the address in OBJ_PTR
L1104:  LDAP                        ;[OBJ_PTR]
L1105:  STA  TMP1E                  ;angle 1: FTRn_HEADX  SINCOS1: angle
L1106:  LDAI #$100
L1107:  A8I  #$0D
L1109:  STA  RET1                   ;SINCOS1: return address  return address: L110D
L110A:  LPAI SINCOS1
L110C:  JMP                         ;call; returns to L110D via RET1

L110D:  LDA  TMP1A                  ;its sine / cosine kept in TMP1C / TMP1D
L110E:  STA  TMP1C
L110F:  LDA  TMP1B
L1110:  STA  TMP1D
L1111:  LDA  OBJ_PTR
L1112:  A4I  #$1
L1113:  STAP                        ;store to OBJ_PTR
L1114:  WS   OBJ_PTR                ;I = the address in OBJ_PTR
L1115:  LDAP                        ;[OBJ_PTR]
L1116:  STA  TMP1E                  ;angle 2: FTRn_HEADY  SINCOS1: angle
L1117:  LDAI #$100
L1118:  A8I  #$1E
L111A:  STA  RET1                   ;SINCOS1: return address
L111B:  LPAI SINCOS1
L111D:  JMP                         ;call; returns to L111E

L111E:  LDA  OBJ_PTR
L111F:  A4I  #$2
L1120:  STAP                        ;store to OBJ_PTR
L1121:  WS   OBJ_PTR                ;I = the address in OBJ_PTR
L1122:  LDAP                        ;[OBJ_PTR]
L1123:  STA  OBJ_PTR                ;OBJ_PTR = FTRn_STATE: dim or bright, and the explosion in DRAWMODEL3D
L1124:  SHR
L1125:  LPAI NEXTOBJ
L1127:  JMP


;------------------------------------------------------------------------------
; DRAWMODEL3D - Rotate, project and draw one model: vertex list TMP16, edge
;   list TMP17, position OBJ_X/Y/Z, angles as sine / cosine pairs TMP1C / TMP1D
;   and TMP1A / TMP1B. Each vertex (bytes - $80, x 4) is rotated, moved to the
;   position, projected (PROJDIV) and kept in the vertex buffer $E0-$FF as an
;   edge first needs it; DRAWEDGES draws the edges between them. With OBJ_PTR
;   (the fighter's FTRn_STATE) 2 or more - an explosion - each edge keeps its
;   length but starts at centre + (start - centre) x state / 8: the pieces
;   bunched at first (state 3), spreading out as the count rises to $18. The
;   title letters use OBJ_PTR = 0. Returns through RET2.
;   Called from L19D6, L19FA, L1A0A (return address in RET2).
;------------------------------------------------------------------------------
DRAWMODEL3D:
L1128:  LDAI #$000
L1129:  A8I  #$FF
L112B:  SETP $1
L112C:  STA  CONST_FF
L112D:  LDA  TMP16
L112E:  S4I  #$3
L112F:  STAP                        ;vertex list - 3: the loop adds 3 first  store to TMP16
L1130:  LDAI #$000
L1131:  S4I  #$2
L1132:  SETP $0
L1133:  STA  TMP03                  ;TMP03: 2 x the vertices projected so far, -2 to start
L1134:  SETP $0
L1135:  LDA  TMP03
L1136:  SHR
L1137:  LPAI DRAWEDGES
L1139:  JOS                         ;odd: the vertex list is done  if the bit shifted out of A was 1 -> DRAWEDGES
L113A:  SETP $1
L113B:  LDA  TMP16
L113C:  A4I  #$3
L113D:  STAP                        ;store to TMP16
L113E:  LKP                         ;table read $1031-$1AE2
L1140:  TST  CONST_FF
L1141:  LPAI L1471
L1143:  JEQ                         ;the end of the vertex list  if A = CONST_FF -> L1471
L1144:  S8I  #$80
L1146:  SHL
L1147:  SHL
L1148:  STA  TMP13                  ;vertex x: (byte - $80) x 4
L1149:  LDA  TMP16
L114A:  A4I  #$1
L114B:  LKP                         ;table read $1032-$1AE3
L114D:  S8I  #$80
L114F:  SHL
L1150:  SHL
L1151:  STA  TMP14                  ;y
L1152:  LDA  TMP16
L1153:  A4I  #$2
L1154:  LKP                         ;table read $1033-$1AE4
L1156:  S8I  #$80
L1158:  SHL
L1159:  SHL
L115A:  STA  TMP15                  ;z
L115B:  SETP $0
L115C:  LDA  TMP03
L115D:  A4I  #$2
L115E:  STAP                        ;one more vertex  store to TMP03
L115F:  SETP $1
L1160:  LDA  TMP13
L1161:  ASR
L1162:  STAP                        ;store to TMP13
L1163:  LDA  TMP14
L1164:  ASR
L1165:  STAP                        ;x and y halved for the rotation  store to TMP14
L1166:  LDA  TMP1C                  ;rotate (x, y) by angle 1 with three multiplies: (sin + cos) x ...
L1167:  ADD  TMP1D
L1168:  STA  RET1
L1169:  SSA
L116A:  LDAI B,#$000
L116B:  LDAI #$800
L116C:  LDA  RET1
L116D:  LPAI L1172
L116F:  JLT                         ;if RET1 < $800 -> L1172
L1170:  LDAI #$000
L1171:  SUBP                        ;RET1
L1172:  TST  TMP13
L1173:  MUL
L1174:  MUL
L1175:  MUL
L1176:  MUL
L1177:  MUL
L1178:  MUL
L1179:  MUL
L117A:  MUL
L117B:  MUL
L117C:  LDAI #$800
L117D:  TST  RET1
L117E:  SSA
L117F:  STA  B,RET1
L1180:  LPAI L1186
L1182:  JLT                         ;if RET1 < $800 -> L1186
L1183:  LDAI #$000
L1184:  SUB  RET1
L1185:  STAP                        ;store to RET1
L1186:  LDA  TMP14
L1187:  ADD  TMP13
L1188:  STAP                        ;store to TMP13
L1189:  SUB  TMP14
L118A:  SUBP                        ;TMP14
L118B:  STAP                        ;store to TMP14
L118C:  SSA
L118D:  LDAI B,#$000
L118E:  LDAI #$800
L118F:  LDA  TMP1C
L1190:  LPAI L1195
L1192:  JLT                         ;if TMP1C < $800 -> L1195
L1193:  LDAI #$000
L1194:  SUBP                        ;TMP1C
L1195:  TST  TMP13
L1196:  MUL
L1197:  MUL
L1198:  MUL
L1199:  MUL
L119A:  MUL
L119B:  MUL
L119C:  MUL
L119D:  MUL
L119E:  MUL
L119F:  LDAI #$800
L11A0:  TST  TMP1C
L11A1:  SSA
L11A2:  STA  B,TMP13
L11A3:  LPAI L11A9
L11A5:  JLT                         ;if TMP1C < $800 -> L11A9
L11A6:  LDAI #$000
L11A7:  SUB  TMP13
L11A8:  STAP                        ;store to TMP13
L11A9:  SSA
L11AA:  LDAI B,#$000
L11AB:  LDAI #$800
L11AC:  LDA  TMP1D
L11AD:  LPAI L11B2
L11AF:  JLT                         ;if TMP1D < $800 -> L11B2
L11B0:  LDAI #$000
L11B1:  SUBP                        ;TMP1D
L11B2:  TST  TMP14
L11B3:  MUL
L11B4:  MUL
L11B5:  MUL
L11B6:  MUL
L11B7:  MUL
L11B8:  MUL
L11B9:  MUL
L11BA:  MUL
L11BB:  MUL
L11BC:  LDAI #$800
L11BD:  TST  TMP1D
L11BE:  SSA
L11BF:  STA  B,TMP14
L11C0:  LPAI L11C6
L11C2:  JLT                         ;if TMP1D < $800 -> L11C6
L11C3:  LDAI #$000
L11C4:  SUB  TMP14
L11C5:  STAP                        ;store to TMP14
L11C6:  LDA  RET1
L11C7:  SUB  TMP13
L11C8:  SHL
L11C9:  STAP                        ;store to TMP13
L11CA:  LDA  RET1
L11CB:  SUB  TMP14
L11CC:  SHL
L11CD:  STAP                        ;store to TMP14
L11CE:  LDA  TMP14
L11CF:  ASR
L11D0:  STAP                        ;store to TMP14
L11D1:  LDA  TMP15
L11D2:  ASR
L11D3:  STAP                        ;store to TMP15
L11D4:  LDA  TMP1A                  ;rotate (y, z) by angle 2
L11D5:  ADD  TMP1B
L11D6:  STA  RET1
L11D7:  SSA
L11D8:  LDAI B,#$000
L11D9:  LDAI #$800
L11DA:  LDA  RET1
L11DB:  LPAI L11E0
L11DD:  JLT                         ;if RET1 < $800 -> L11E0
L11DE:  LDAI #$000
L11DF:  SUBP                        ;RET1
L11E0:  TST  TMP14
L11E1:  MUL
L11E2:  MUL
L11E3:  MUL
L11E4:  MUL
L11E5:  MUL
L11E6:  MUL
L11E7:  MUL
L11E8:  MUL
L11E9:  MUL
L11EA:  LDAI #$800
L11EB:  TST  RET1
L11EC:  SSA
L11ED:  STA  B,RET1
L11EE:  LPAI L11F4
L11F0:  JLT                         ;if RET1 < $800 -> L11F4
L11F1:  LDAI #$000
L11F2:  SUB  RET1
L11F3:  STAP                        ;store to RET1
L11F4:  LDA  TMP15
L11F5:  ADD  TMP14
L11F6:  STAP                        ;store to TMP14
L11F7:  SUB  TMP15
L11F8:  SUBP                        ;TMP15
L11F9:  STAP                        ;store to TMP15
L11FA:  SSA
L11FB:  LDAI B,#$000
L11FC:  LDAI #$800
L11FD:  LDA  TMP1A
L11FE:  LPAI L1203
L1200:  JLT                         ;if TMP1A < $800 -> L1203
L1201:  LDAI #$000
L1202:  SUBP                        ;TMP1A
L1203:  TST  TMP14
L1204:  MUL
L1205:  MUL
L1206:  MUL
L1207:  MUL
L1208:  MUL
L1209:  MUL
L120A:  MUL
L120B:  MUL
L120C:  MUL
L120D:  LDAI #$800
L120E:  TST  TMP1A
L120F:  SSA
L1210:  STA  B,TMP14
L1211:  LPAI L1217
L1213:  JLT                         ;if TMP1A < $800 -> L1217
L1214:  LDAI #$000
L1215:  SUB  TMP14
L1216:  STAP                        ;store to TMP14
L1217:  SSA
L1218:  LDAI B,#$000
L1219:  LDAI #$800
L121A:  LDA  TMP1B
L121B:  LPAI L1220
L121D:  JLT                         ;if TMP1B < $800 -> L1220
L121E:  LDAI #$000
L121F:  SUBP                        ;TMP1B
L1220:  TST  TMP15
L1221:  MUL
L1222:  MUL
L1223:  MUL
L1224:  MUL
L1225:  MUL
L1226:  MUL
L1227:  MUL
L1228:  MUL
L1229:  MUL
L122A:  LDAI #$800
L122B:  TST  TMP1B
L122C:  SSA
L122D:  STA  B,TMP15
L122E:  LPAI L1234
L1230:  JLT                         ;if TMP1B < $800 -> L1234
L1231:  LDAI #$000
L1232:  SUB  TMP15
L1233:  STAP                        ;store to TMP15
L1234:  LDA  RET1
L1235:  SUB  TMP14
L1236:  SHL
L1237:  STAP                        ;store to TMP14
L1238:  LDA  RET1
L1239:  SUB  TMP15
L123A:  SHL
L123B:  STAP                        ;store to TMP15
L123C:  LDA  TMP13
L123D:  ASR
L123E:  STAP                        ;store to TMP13
L123F:  LDA  TMP15
L1240:  ASR
L1241:  STAP                        ;store to TMP15
L1242:  LDA  TMP1C                  ;rotate (x, z) by angle 1 again: a fighter banks as it turns
L1243:  ADD  TMP1D
L1244:  STA  RET1
L1245:  SSA
L1246:  LDAI B,#$000
L1247:  LDAI #$800
L1248:  LDA  RET1
L1249:  LPAI L124E
L124B:  JLT                         ;if RET1 < $800 -> L124E
L124C:  LDAI #$000
L124D:  SUBP                        ;RET1
L124E:  TST  TMP13
L124F:  MUL
L1250:  MUL
L1251:  MUL
L1252:  MUL
L1253:  MUL
L1254:  MUL
L1255:  MUL
L1256:  MUL
L1257:  MUL
L1258:  LDAI #$800
L1259:  TST  RET1
L125A:  SSA
L125B:  STA  B,RET1
L125C:  LPAI L1262
L125E:  JLT                         ;if RET1 < $800 -> L1262
L125F:  LDAI #$000
L1260:  SUB  RET1
L1261:  STAP                        ;store to RET1
L1262:  LDA  TMP15
L1263:  ADD  TMP13
L1264:  STAP                        ;store to TMP13
L1265:  SUB  TMP15
L1266:  SUBP                        ;TMP15
L1267:  STAP                        ;store to TMP15
L1268:  SSA
L1269:  LDAI B,#$000
L126A:  LDAI #$800
L126B:  LDA  TMP1C
L126C:  LPAI L1271
L126E:  JLT                         ;if TMP1C < $800 -> L1271
L126F:  LDAI #$000
L1270:  SUBP                        ;TMP1C
L1271:  TST  TMP13
L1272:  MUL
L1273:  MUL
L1274:  MUL
L1275:  MUL
L1276:  MUL
L1277:  MUL
L1278:  MUL
L1279:  MUL
L127A:  MUL
L127B:  LDAI #$800
L127C:  TST  TMP1C
L127D:  SSA
L127E:  STA  B,TMP13
L127F:  LPAI L1285
L1281:  JLT                         ;if TMP1C < $800 -> L1285
L1282:  LDAI #$000
L1283:  SUB  TMP13
L1284:  STAP                        ;store to TMP13
L1285:  SSA
L1286:  LDAI B,#$000
L1287:  LDAI #$800
L1288:  LDA  TMP1D
L1289:  LPAI L128E
L128B:  JLT                         ;if TMP1D < $800 -> L128E
L128C:  LDAI #$000
L128D:  SUBP                        ;TMP1D
L128E:  TST  TMP15
L128F:  MUL
L1290:  MUL
L1291:  MUL
L1292:  MUL
L1293:  MUL
L1294:  MUL
L1295:  MUL
L1296:  MUL
L1297:  MUL
L1298:  LDAI #$800
L1299:  TST  TMP1D
L129A:  SSA
L129B:  STA  B,TMP15
L129C:  LPAI L12A2
L129E:  JLT                         ;if TMP1D < $800 -> L12A2
L129F:  LDAI #$000
L12A0:  SUB  TMP15
L12A1:  STAP                        ;store to TMP15
L12A2:  LDA  RET1
L12A3:  SUB  TMP13
L12A4:  SHL
L12A5:  STAP                        ;store to TMP13
L12A6:  LDA  RET1
L12A7:  SUB  TMP15
L12A8:  SHL
L12A9:  STAP                        ;store to TMP15
L12AA:  LDA  TMP13
L12AB:  ASR
L12AC:  ASR
L12AD:  ADD  OBJ_X
L12AE:  SETP $0
L12AF:  STA  TMP05                  ;x / 4 + OBJ_X
L12B0:  SETP $1
L12B1:  LDA  TMP14
L12B2:  ASR
L12B3:  ASR
L12B4:  ADD  OBJ_Y
L12B5:  SETP $0
L12B6:  STA  TMP06                  ;y / 4 + OBJ_Y
L12B7:  SETP $1
L12B8:  LDA  TMP15
L12B9:  ASR
L12BA:  ASR
L12BB:  ADD  OBJ_Z
L12BC:  SHR
L12BD:  SETP $0
L12BE:  STA  TMP09                  ;(z / 4 + OBJ_Z) / 2: the depth
L12BF:  LDAI #$200
L12C0:  STA  TMP0D                  ;$200 / depth, as in PROJDIV
L12C1:  LDAI #$000
L12C2:  STA  TMP04
L12C3:  LDA  TMP0D
L12C4:  TST  TMP09
L12C5:  LPAI L1333
L12C7:  JLT                         ;if TMP09 < TMP0D -> L1333
L12C8:  SSA
L12C9:  LDAI B,#$000
L12CA:  SHLB
L12CB:  SSA
L12CC:  A4I  B,#$1
L12CD:  SUBP                        ;TMP09
L12CE:  LPAI L12D4
L12D0:  JLT                         ;if TMP09 < A -> L12D4
L12D1:  ADDP                        ;TMP09
L12D2:  SSA
L12D3:  S4I  B,#$1
L12D4:  SHLB
L12D5:  SSA
L12D6:  A4I  B,#$1
L12D7:  SUBP
L12D8:  LPAI L12DE
L12DA:  JLT                         ;if ? < A -> L12DE
L12DB:  ADDP
L12DC:  SSA
L12DD:  S4I  B,#$1
L12DE:  SHLB
L12DF:  SSA
L12E0:  A4I  B,#$1
L12E1:  SUBP
L12E2:  LPAI L12E8
L12E4:  JLT                         ;if ? < A -> L12E8
L12E5:  ADDP
L12E6:  SSA
L12E7:  S4I  B,#$1
L12E8:  SHLB
L12E9:  SSA
L12EA:  A4I  B,#$1
L12EB:  SUBP
L12EC:  LPAI L12F2
L12EE:  JLT                         ;if ? < A -> L12F2
L12EF:  ADDP
L12F0:  SSA
L12F1:  S4I  B,#$1
L12F2:  SHLB
L12F3:  SSA
L12F4:  A4I  B,#$1
L12F5:  SUBP
L12F6:  LPAI L12FC
L12F8:  JLT                         ;if ? < A -> L12FC
L12F9:  ADDP
L12FA:  SSA
L12FB:  S4I  B,#$1
L12FC:  SHLB
L12FD:  SSA
L12FE:  A4I  B,#$1
L12FF:  SUBP
L1300:  LPAI L1306
L1302:  JLT                         ;if ? < A -> L1306
L1303:  ADDP
L1304:  SSA
L1305:  S4I  B,#$1
L1306:  SHLB
L1307:  SSA
L1308:  A4I  B,#$1
L1309:  SUBP
L130A:  LPAI L1310
L130C:  JLT                         ;if ? < A -> L1310
L130D:  ADDP
L130E:  SSA
L130F:  S4I  B,#$1
L1310:  SHLB
L1311:  SSA
L1312:  A4I  B,#$1
L1313:  SUBP
L1314:  LPAI L131A
L1316:  JLT                         ;if ? < A -> L131A
L1317:  ADDP
L1318:  SSA
L1319:  S4I  B,#$1
L131A:  SHLB
L131B:  SSA
L131C:  A4I  B,#$1
L131D:  SUBP
L131E:  LPAI L1324
L1320:  JLT                         ;if ? < A -> L1324
L1321:  ADDP
L1322:  SSA
L1323:  S4I  B,#$1
L1324:  SHLB
L1325:  SSA
L1326:  A4I  B,#$1
L1327:  SUBP
L1328:  LPAI L132E
L132A:  JLT                         ;if ? < A -> L132E
L132B:  ADDP
L132C:  SSA
L132D:  S4I  B,#$1
L132E:  SSA
L132F:  STA  B,TMP09
L1330:  LPAI L133B
L1332:  JMP

L1333:  SUBP
L1334:  STA  TMP0D
L1335:  LDA  TMP04
L1336:  A4I  #$1
L1337:  STAP                        ;store to TMP04
L1338:  LPAI L12C3
L133A:  JMP

L133B:  SSA
L133C:  LDAI B,#$000
L133D:  LDAI #$800
L133E:  LDA  TMP05
L133F:  LPAI L1344
L1341:  JLT                         ;if TMP05 < $800 -> L1344
L1342:  LDAI #$000
L1343:  SUBP                        ;TMP05
L1344:  TST  TMP09
L1345:  MUL
L1346:  MUL
L1347:  MUL
L1348:  MUL
L1349:  MUL
L134A:  MUL
L134B:  MUL
L134C:  MUL
L134D:  MUL
L134E:  MUL
L134F:  MUL
L1350:  SSA
L1351:  STA  B,TMP07
L1352:  LDAI #$800
L1353:  TST  TMP05
L1354:  LPAI L135A
L1356:  JLT                         ;if TMP05 < $800 -> L135A
L1357:  LDAI #$000
L1358:  SUB  TMP07
L1359:  STAP                        ;store to TMP07
L135A:  SSA
L135B:  LDAI B,#$000
L135C:  LDAI #$800
L135D:  LDA  TMP06
L135E:  LPAI L1363
L1360:  JLT                         ;if TMP06 < $800 -> L1363
L1361:  LDAI #$000
L1362:  SUBP                        ;TMP06
L1363:  TST  TMP09
L1364:  MUL
L1365:  MUL
L1366:  MUL
L1367:  MUL
L1368:  MUL
L1369:  MUL
L136A:  MUL
L136B:  MUL
L136C:  MUL
L136D:  MUL
L136E:  MUL
L136F:  SSA
L1370:  STA  B,TMP08
L1371:  LDAI #$800
L1372:  TST  TMP06
L1373:  LPAI L1379
L1375:  JLT                         ;if TMP06 < $800 -> L1379
L1376:  LDAI #$000
L1377:  SUB  TMP08
L1378:  STAP                        ;store to TMP08
L1379:  SSA
L137A:  LDAI B,#$000
L137B:  SSA
L137C:  SUB  B,TMP04
L137D:  LPAI L138B
L137F:  JEQ                         ;if TMP04 = 0 -> L138B
L1380:  LPAI L1382
L1382:  LDA  TMP05
L1383:  ADD  TMP07
L1384:  STAP                        ;store to TMP07
L1385:  LDA  TMP06
L1386:  ADD  TMP08
L1387:  STAP                        ;store to TMP08
L1388:  SSA
L1389:  A4I  B,#$1
L138A:  JCZ                         ;until B + 1 carries (reaches $1000) -> L1382
L138B:  LDA  TMP03
L138C:  A8I  #$E0
L138E:  STA  TMP0E
L138F:  A4I  #$1
L1390:  STA  TMP0F
L1391:  LDAI #$200
L1392:  ADD  TMP07
L1393:  STAP                        ;store to TMP07
L1394:  WS   TMP0E                  ;I = the address in TMP0E
L1395:  STAP                        ;screen x + $200 into the vertex buffer  store to [TMP0E]
L1396:  LDAI #$300
L1397:  SHR
L1398:  ADD  TMP08
L1399:  STAP                        ;store to TMP08
L139A:  WS   TMP0F                  ;I = the address in TMP0F
L139B:  STAP                        ;screen y + $180  store to [TMP0F]
DRAWEDGES:
L139C:  SETP $1
L139D:  LDA  TMP17
L139E:  LKP                         ;the next edge byte: two vertex numbers  table read $105F-$1AF2
L13A0:  TST  CONST_FF
L13A1:  LPAI MODELRET
L13A3:  JEQ                         ;the end of the edges  if A = CONST_FF -> MODELRET
L13A4:  LPAI L1134
L13A6:  JVN                         ;while the vector generator is busy -> L1134
L13A7:  SETP $0
L13A8:  STA  TMP0B
L13A9:  SHR
L13AA:  SHR
L13AB:  SHR
L13AC:  SHR
L13AD:  SHL                         ;2 x the first vertex
L13AE:  TST  TMP03
L13AF:  JLT                         ;not projected yet: project the next vertex first  if TMP03 < A -> L1134
L13B0:  STA  TMP0A
L13B1:  LDAI #$000
L13B2:  A4I  #$F
L13B3:  TST  TMP0B
L13B4:  ANDP                        ;TMP0B
L13B5:  SHL
L13B6:  STAP                        ;2 x the second vertex  store to TMP0B
L13B7:  TST  TMP03
L13B8:  JLT                         ;not projected yet  if TMP03 < A -> L1134
L13B9:  LDA  TMP0A
L13BA:  A8I  #$E0
L13BC:  STA  TMP0E
L13BD:  A4I  #$1
L13BE:  STA  TMP0F
L13BF:  WS   TMP0F                  ;I = the address in TMP0F
L13C0:  LDAP                        ;[TMP0F]
L13C1:  STA  TMP06                  ;the first vertex: y
L13C2:  LDAI #$300
L13C3:  TST  TMP06
L13C4:  LPAI L1454
L13C6:  JCZ                         ;off the screen: skip the edge  if $300 < TMP06 -> L1454
L13C7:  WS   TMP0E                  ;I = the address in TMP0E
L13C8:  LDAP                        ;[TMP0E]
L13C9:  STA  TMP05                  ;x
L13CA:  LDAI #$400
L13CB:  TST  TMP05
L13CC:  JCZ                         ;off the screen  if $400 < TMP05 -> L1454
L13CD:  LDA  TMP0B
L13CE:  A8I  #$E0
L13D0:  STA  TMP0E
L13D1:  A4I  #$1
L13D2:  STA  TMP0F
L13D3:  WS   TMP0F                  ;I = the address in TMP0F
L13D4:  LDAP                        ;[TMP0F]
L13D5:  STA  TMP08                  ;the second vertex: y
L13D6:  LDAI #$300
L13D7:  TST  TMP08
L13D8:  JCZ                         ;off the screen  if $300 < TMP08 -> L1454
L13D9:  WS   TMP0E                  ;I = the address in TMP0E
L13DA:  LDAP                        ;[TMP0E]
L13DB:  STA  TMP07                  ;x
L13DC:  LDAI #$400
L13DD:  TST  TMP07
L13DE:  JCZ                         ;off the screen  if $400 < TMP07 -> L1454
L13DF:  LDA  TMP08
L13E0:  SUB  TMP06
L13E1:  STA  TMP08                  ;dy
L13E2:  LDA  TMP07
L13E3:  SUB  TMP05
L13E4:  STA  TMP07                  ;dx
L13E5:  LDAI #$000
L13E6:  A4I  #$2
L13E7:  SETP $1
L13E8:  TST  OBJ_PTR
L13E9:  LPAI L141E
L13EB:  JLT                         ;not exploding: draw as it is  if OBJ_PTR < 2 -> L141E
L13EC:  SETP $0
L13ED:  LDA  TMP05
L13EE:  SETP $2
L13EF:  SUB  CTR_X
L13F0:  SHL
L13F1:  SHL
L13F2:  SETP $0
L13F3:  STA  TMP0C                  ;exploding: push the edge's start out from the centre,
L13F4:  SSA
L13F5:  LDAI B,#$000
L13F6:  SETP $1
L13F7:  LDA  OBJ_PTR
L13F8:  SETP $0
L13F9:  TST  TMP0C
L13FA:  MUL
L13FB:  MUL
L13FC:  MUL
L13FD:  MUL
L13FE:  MUL
L13FF:  SETP $2
L1400:  SSA
L1401:  ADD  B,CTR_X
L1402:  SETP $0
L1403:  SSA
L1404:  STA  B,TMP05                ;start = centre + (start - centre) x OBJ_PTR / 8 (5 MUL steps)
L1405:  SETP $0
L1406:  LDA  TMP06
L1407:  SETP $2
L1408:  SUB  CTR_Y
L1409:  SHL
L140A:  SHL
L140B:  SETP $0
L140C:  STA  TMP0C
L140D:  SSA
L140E:  LDAI B,#$000
L140F:  SETP $1
L1410:  LDA  OBJ_PTR
L1411:  SETP $0
L1412:  TST  TMP0C
L1413:  MUL
L1414:  MUL
L1415:  MUL
L1416:  MUL
L1417:  MUL
L1418:  SETP $2
L1419:  SSA
L141A:  ADD  B,CTR_Y
L141B:  SETP $0
L141C:  SSA
L141D:  STA  B,TMP06                ;and the same for y
L141E:  SETP $0
L141F:  LDA  TMP05
L1420:  SSA
L1421:  LDA  B,TMP06
L1422:  LPAI L1422
L1424:  JVN                         ;while the vector generator is busy -> L1422
L1425:  IV                          ;beam to the edge's start
L1426:  LDAI #$800
L1427:  LDA  TMP07
L1428:  LPAI L142D
L142A:  JLT                         ;if TMP07 < $800 -> L142D
L142B:  LDAI #$000
L142C:  SUBP                        ;TMP07
L142D:  STA  TMP0C
L142E:  STA  TMP0E
L142F:  LDAI #$800
L1430:  LDA  TMP08
L1431:  LPAI L1436
L1433:  JLT                         ;if TMP08 < $800 -> L1436
L1434:  LDAI #$000
L1435:  SUBP                        ;TMP08
L1436:  STA  TMP0F
L1437:  ADD  TMP0E
L1438:  STAP                        ;|dx| + |dy|  store to TMP0E
L1439:  S4I  #$3
L143A:  LPAI L1454
L143C:  JCZ                         ;shorter than 3: not worth drawing  if A < 3 -> L1454
L143D:  LDAI #$000
L143E:  S8I  #$08
L1440:  A4I  #$1
L1441:  LPAI L1440
L1443:  JCZ                         ;count up to 0 (a delay of $8 loops) -> L1440
L1444:  LDAI #$200
L1445:  S4I  #$7
L1446:  TST  TMP0F
L1447:  LPAI L145B
L1449:  JCZ                         ;a long edge ...  if $1F9 < TMP0F -> L145B
L144A:  TST  TMP0C
L144B:  JCZ                         ;... would be drawn in two halves (never in the traces)  if $1F9 < TMP0C -> L145B
L144C:  LDA  TMP07
L144D:  SSA
L144E:  LDA  B,TMP08
L144F:  NV
L1450:  ADD  TMP05
L1451:  SSA
L1452:  ADD  B,TMP06
L1453:  DV                          ;the edge
L1454:  SETP $1
L1455:  LDA  TMP17
L1456:  A4I  #$1
L1457:  STAP                        ;the next edge  store to TMP17
L1458:  LPAI DRAWEDGES
L145A:  JMP

;[static] not executed in the traces; reached by following the jumps
L145B:  SSA
L145C:  LDA  B,CONST_FF
L145D:  SHRB
L145E:  SSA
L145F:  STAP B                      ;store to CONST_FF
L1460:  LDA  TMP17
L1461:  ASR
L1462:  STAP                        ;store to TMP17
L1463:  NV
L1464:  ADD  TMP15
L1465:  SSA
L1466:  ADD  B,TMP16
L1467:  DV
L1468:  LDA  CONST_FF
L1469:  ADD  TMP16
L146A:  STAP                        ;store to TMP16
L146B:  LDA  TMP17
L146C:  ADD  TMP15
L146D:  STAP                        ;store to TMP15
L146E:  LPAI L141E
L1470:  JMP

L1471:  SETP $0
L1472:  LDA  TMP03
L1473:  A4I  #$1
L1474:  STAP                        ;the vertex list ended: TMP03 odd  store to TMP03
L1475:  SETP $1
L1476:  LPAI DRAWEDGES
L1478:  JMP

MODELRET:
L1479:  SETP $2
L147A:  TST  RET2
L147B:  LPAP                        ;back to DRAWMODEL's caller  J = the address in RET2
L147C:  JMP                         ;J from RAM -> TESTLOOP, L1094, L10A7, L19D7, L19FB, L1A0B

DRAWFTRSRET:
L147D:  SETP $0
L147E:  TST  RET0
L147F:  LPAP                        ;back to bank 1's frame code  J = the address in RET0
L1480:  JMP                         ;J from RAM -> DRAWHUD, TOMAIN

;$1481-$1574, read by LKP at L10DE, L10E4, L113E, L114B, L1154, L139E
MODELS:
FTRMODEL1:
L1481:  .byte $B1, $04              ;Fighter 1: edge list at $14B1
L1483:  .byte $6C, $82, $94         ;vertex  0: x  -20  y   +2  z  +20
L1486:  .byte $6C, $82, $C6         ;vertex  1: x  -20  y   +2  z  +70
L1489:  .byte $62, $8C, $C6         ;vertex  2: x  -30  y  +12  z  +70
L148C:  .byte $62, $8C, $94         ;vertex  3: x  -30  y  +12  z  +20
L148F:  .byte $62, $74, $58         ;vertex  4: x  -30  y  -12  z  -40
L1492:  .byte $80, $74, $3A         ;vertex  5: x   +0  y  -12  z  -70
L1495:  .byte $9E, $74, $58         ;vertex  6: x  +30  y  -12  z  -40
L1498:  .byte $94, $82, $94         ;vertex  7: x  +20  y   +2  z  +20
L149B:  .byte $9E, $8C, $94         ;vertex  8: x  +30  y  +12  z  +20
L149E:  .byte $9E, $8C, $C6         ;vertex  9: x  +30  y  +12  z  +70
L14A1:  .byte $94, $82, $C6         ;vertex 10: x  +20  y   +2  z  +70
L14A4:  .byte $80, $82, $A8         ;vertex 11: x   +0  y   +2  z  +40
L14A7:  .byte $6C, $82, $6C         ;vertex 12: x  -20  y   +2  z  -20
L14AA:  .byte $80, $82, $58         ;vertex 13: x   +0  y   +2  z  -40
L14AD:  .byte $94, $82, $6C         ;vertex 14: x  +20  y   +2  z  -20
L14B0:  .byte $FF                   ;end of vertices
FTRMODEL1_EDGES:
L14B1:  .byte $01, $12, $23, $30, $04, $45, $56, $67  ;edges 0-1 1-2 2-3 3-0 0-4 4-5 5-6 6-7
L14B9:  .byte $78, $89, $9A, $A7, $7B, $B0, $0C, $C4  ;edges 7-8 8-9 9-10 10-7 7-11 11-0 0-12 12-4
L14C1:  .byte $CD, $D5, $DE, $E6, $E7  ;edges 12-13 13-5 13-14 14-6 14-7
L14C6:  .byte $FF                   ;end of edges
FTRMODEL2:
L14C7:  .byte $EE, $04              ;Fighter 2: edge list at $14EE
L14C9:  .byte $80, $80, $62         ;vertex  0: x   +0  y   +0  z  -30
L14CC:  .byte $3A, $64, $C6         ;vertex  1: x  -70  y  -28  z  +70
L14CF:  .byte $6C, $7C, $C6         ;vertex  2: x  -20  y   -4  z  +70
L14D2:  .byte $94, $7C, $C6         ;vertex  3: x  +20  y   -4  z  +70
L14D5:  .byte $C6, $64, $C6         ;vertex  4: x  +70  y  -28  z  +70
L14D8:  .byte $6C, $80, $4E         ;vertex  5: x  -20  y   +0  z  -50
L14DB:  .byte $80, $80, $3A         ;vertex  6: x   +0  y   +0  z  -70
L14DE:  .byte $94, $80, $4E         ;vertex  7: x  +20  y   +0  z  -50
L14E1:  .byte $80, $94, $4E         ;vertex  8: x   +0  y  +20  z  -50
L14E4:  .byte $80, $6C, $4E         ;vertex  9: x   +0  y  -20  z  -50
L14E7:  .byte $76, $86, $C6         ;vertex 10: x  -10  y   +6  z  +70
L14EA:  .byte $8A, $86, $C6         ;vertex 11: x  +10  y   +6  z  +70
L14ED:  .byte $FF                   ;end of vertices
FTRMODEL2_EDGES:
L14EE:  .byte $01, $12, $23, $34, $40, $05, $56, $67  ;edges 0-1 1-2 2-3 3-4 4-0 0-5 5-6 6-7
L14F6:  .byte $70, $08, $86, $69, $90, $02, $2A, $AB  ;edges 7-0 0-8 8-6 6-9 9-0 0-2 2-10 10-11
L14FE:  .byte $B3, $30, $0A, $B0    ;edges 11-3 3-0 0-10 11-0
L1502:  .byte $FF                   ;end of edges
FTRMODEL3:
L1503:  .byte $27, $05              ;Fighter 3: edge list at $1527
L1505:  .byte $80, $78, $62         ;vertex  0: x   +0  y   -8  z  -30
L1508:  .byte $9E, $78, $80         ;vertex  1: x  +30  y   -8  z   +0
L150B:  .byte $80, $78, $9E         ;vertex  2: x   +0  y   -8  z  +30
L150E:  .byte $62, $78, $80         ;vertex  3: x  -30  y   -8  z   +0
L1511:  .byte $80, $8A, $80         ;vertex  4: x   +0  y  +10  z   +0
L1514:  .byte $80, $8A, $C6         ;vertex  5: x   +0  y  +10  z  +70
L1517:  .byte $80, $9E, $C6         ;vertex  6: x   +0  y  +30  z  +70
L151A:  .byte $9E, $6E, $C6         ;vertex  7: x  +30  y  -18  z  +70
L151D:  .byte $B2, $64, $C6         ;vertex  8: x  +50  y  -28  z  +70
L1520:  .byte $62, $6E, $C6         ;vertex  9: x  -30  y  -18  z  +70
L1523:  .byte $4E, $64, $C6         ;vertex 10: x  -50  y  -28  z  +70
L1526:  .byte $FF                   ;end of vertices
FTRMODEL3_EDGES:
L1527:  .byte $01, $12, $23, $30, $04, $42, $25, $56  ;edges 0-1 1-2 2-3 3-0 0-4 4-2 2-5 5-6
L152F:  .byte $62, $27, $78, $82, $29, $9A, $A2, $34  ;edges 6-2 2-7 7-8 8-2 2-9 9-10 10-2 3-4
L1537:  .byte $41                   ;edges 4-1
L1538:  .byte $FF                   ;end of edges
FTRMODEL4:
L1539:  .byte $5D, $05              ;Fighter 4: edge list at $155D
L153B:  .byte $80, $80, $80         ;vertex  0: x   +0  y   +0  z   +0
L153E:  .byte $44, $86, $BE         ;vertex  1: x  -60  y   +6  z  +62
L1541:  .byte $6C, $76, $BE         ;vertex  2: x  -20  y  -10  z  +62
L1544:  .byte $94, $76, $BE         ;vertex  3: x  +20  y  -10  z  +62
L1547:  .byte $BC, $86, $BE         ;vertex  4: x  +60  y   +6  z  +62
L154A:  .byte $80, $6C, $6C         ;vertex  5: x   +0  y  -20  z  -20
L154D:  .byte $6C, $80, $58         ;vertex  6: x  -20  y   +0  z  -40
L1550:  .byte $70, $86, $62         ;vertex  7: x  -16  y   +6  z  -30
L1553:  .byte $94, $80, $58         ;vertex  8: x  +20  y   +0  z  -40
L1556:  .byte $90, $86, $62         ;vertex  9: x  +16  y   +6  z  -30
L1559:  .byte $80, $80, $44         ;vertex 10: x   +0  y   +0  z  -60
L155C:  .byte $FF                   ;end of vertices
FTRMODEL4_EDGES:
L155D:  .byte $01, $12, $23, $34, $40, $02, $25, $53  ;edges 0-1 1-2 2-3 3-4 4-0 0-2 2-5 5-3
L1565:  .byte $30, $06, $67, $70, $05, $56, $68, $80  ;edges 3-0 0-6 6-7 7-0 0-5 5-6 6-8 8-0
L156D:  .byte $09, $98, $85, $5A, $A6, $79, $8A  ;edges 0-9 9-8 8-5 5-10 10-6 7-9 8-10
L1574:  .byte $FF                   ;end of edges

;------------------------------------------------------------------------------
; SINCOS1 - Bank 1 copy of SINCOS0 (table SINTAB1). Returns through RET1.
;   Called from L110C, L111D, L198E (return address in RET1).
;------------------------------------------------------------------------------
SINCOS1:
L1575:  LDAI #$000
L1576:  A8I  #$7F
L1578:  TST  TMP1E
L1579:  ANDP                        ;TMP1E
L157A:  STAP                        ;store to TMP1E
L157B:  LDAI #$500
L157C:  A8I  #$F6
L157E:  STA  TMP1A
L157F:  LDAI #$000
L1580:  A8I  #$20
L1582:  TST  TMP1E
L1583:  LPAI L159F
L1585:  JLT                         ;if TMP1E < $20 -> L159F
L1586:  SHL
L1587:  TST  TMP1E
L1588:  LPAI L15AB
L158A:  JLT                         ;if TMP1E < A -> L15AB
L158B:  A8I  #$20
L158D:  TST  TMP1E
L158E:  LPAI L15BF
L1590:  JLT                         ;if TMP1E < A -> L15BF
L1591:  LDA  TMP1A
L1592:  ADD  TMP1E
L1593:  S8I  #$80
L1595:  LKP                         ;table read $15D6-$15F5
L1597:  STA  TMP1B
L1598:  LDA  TMP1A
L1599:  A8I  #$60
L159B:  SUB  TMP1E
L159C:  LPAI L15CD
L159E:  JMP

L159F:  LDA  TMP1A
L15A0:  SUB  TMP1E
L15A1:  LKP                         ;table read $15D7-$15F6
L15A3:  STA  TMP1B
L15A4:  LDAI #$500
L15A5:  A8I  #$D6
L15A7:  ADD  TMP1E
L15A8:  LPAI L15B9
L15AA:  JMP

L15AB:  LDA  TMP1A
L15AC:  ADD  TMP1E
L15AD:  S8I  #$40
L15AF:  LKP                         ;table read $15D6-$15F5
L15B1:  STA  TMP1B
L15B2:  LDAI #$000
L15B3:  SUBP                        ;TMP1B
L15B4:  STAP                        ;store to TMP1B
L15B5:  LDA  TMP1A
L15B6:  A8I  #$20
L15B8:  SUB  TMP1E
L15B9:  LKP                         ;table read $15D6-$15F6
L15BB:  STA  TMP1A
L15BC:  LPAI L15D3
L15BE:  JMP

L15BF:  LDA  TMP1A
L15C0:  A8I  #$40
L15C2:  SUB  TMP1E
L15C3:  LKP                         ;table read $15D7-$15F6
L15C5:  STA  TMP1B
L15C6:  LDAI #$000
L15C7:  SUBP                        ;TMP1B
L15C8:  STAP                        ;store to TMP1B
L15C9:  LDA  TMP1A
L15CA:  ADD  TMP1E
L15CB:  S8I  #$60
L15CD:  LKP                         ;table read $15D6-$15F6
L15CF:  STA  TMP1A
L15D0:  LDAI #$000
L15D1:  SUBP                        ;TMP1A
L15D2:  STAP                        ;store to TMP1A
L15D3:  TST  RET1
L15D4:  LPAP                        ;J = the address in RET1
L15D5:  JMP                         ;J from RAM -> L110D, L111E, L198F, TITLESTEP

;$15D6-$15FF, read by LKP at L1595, L15A1, L15AF, L15B9, L15C3, L15CD
SINTAB1:
L15D6:  .byte $00, $0D, $19, $25, $32, $3E, $4A, $56  ;sine x 255, entries 0-7 (32 = a quarter turn)
L15DE:  .byte $62, $6D, $78, $83, $8E, $98, $A2, $AB  ;sine x 255, entries 8-15 (32 = a quarter turn)
L15E6:  .byte $B4, $BD, $C5, $CD, $D4, $DB, $E1, $E7  ;sine x 255, entries 16-23 (32 = a quarter turn)
L15EE:  .byte $EC, $F0, $F4, $F7, $FA, $FC, $FE, $FF  ;sine x 255, entries 24-31 (32 = a quarter turn)
L15F6:  .byte $FF                   ;sine x 255, entry 32: sin 90 degrees
L15F7:  .byte $E2, $FF, $20, $53, $42, $42, $20, $41
L15FF:  .byte $4E

;------------------------------------------------------------------------------
; DRAWHUD - Score lines: 'SCORE' and 'HIGH SCORE' with their values, the shield
;   points and the count of fighters that got past; then the coin and credit
;   logic and the attract / start state.
;   Reached by the jump through RAM at L1480.
;------------------------------------------------------------------------------
DRAWHUD:
L1600:  NOP
L1601:  SSA
L1602:  LDAI B,#$200
L1603:  SSA
L1604:  A8I  B,#$76
L1606:  LDAI #$000
L1607:  A8I  #$A0
L1609:  LPAI L160B
L160B:  JVN                         ;while the vector generator is busy -> L160B
L160C:  IV                          ;beam to ($276, $A0)
L160D:  LDAI #$000
L160E:  S8I  #$38
L1610:  A4I  #$1
L1611:  LPAI L1610
L1613:  JCZ                         ;count up to 0 (a delay of $38 loops) -> L1610
L1614:  LDAI #$000
L1615:  SETP $6
L1616:  TST  FTRS_LEFT
L1617:  LPAI HUDSCORE
L1619:  JCZ                         ;in a game the label is not printed  if FTRS_LEFT > 0 -> HUDSCORE
L161A:  OUT  OUT_INTENSITY          ;dim
L161B:  LDAI #$000
L161C:  A8I  #$96
L161E:  SETP $0
L161F:  STA  TMP03                  ;PRINT: x
L1620:  LDAI #$200
L1621:  A8I  #$8A
L1623:  STA  TMP04                  ;PRINT: y
L1624:  LDAI #$000
L1625:  A8I  #$11
L1627:  STA  TMP0E                  ;PRINT: beam-settle delay
L1628:  LDAI #$000
L1629:  STA  TMP0F                  ;PRINT: 0 = string, 3 = BCD number
L162A:  LDAI #$600
L162B:  A8I  #$33
L162D:  STA  TMP05                  ;the string at $1634 (PRINT starts at TMP05 + 1)  PRINT: what to print (string in bank 1 / RAM word)
L162E:  A8I  #$07
L1630:  STA  RET0                   ;return address: HUDSCORE ($633 + 7)  PRINT: return address
L1631:  LPAI PRINT
L1633:  JMP

;$1634-$1639, read by LKP at L1B11
TXT_SCORE:
L1634:  .byte $53, $43, $4F, $52, $45, $FF  ;"SCORE", $FF

;------------------------------------------------------------------------------
; HUDSCORE - The player's score: brightened by the hit flash (HIT_FLASH),
;   SCORE_HI / SCORE_LO printed under SCORE.
;   Reached by the jump through RAM at L1B6D.
;------------------------------------------------------------------------------
HUDSCORE:
L163A:  LDAI #$000
L163B:  SETP $7
L163C:  LDA  HIT_FLASH
L163D:  LPAI L1644
L163F:  JEQ                         ;if HIT_FLASH = 0 -> L1644
L1640:  S4I  #$1
L1641:  STAP                        ;the hit flash counts down  store to HIT_FLASH
L1642:  LDAI #$000
L1643:  A4I  #$1                    ;bright while it runs
L1644:  OUT  OUT_INTENSITY          ;vector intensity: A bit 0 = 1 bright, 0 dim
L1645:  LDAI #$000
L1646:  A8I  #$10
L1648:  OUT  OUT_SND_DATA           ;sound register bit 7 (no sample in the AAE driver)  sound: bit 7 off
L1649:  SHR
L164A:  OUT  OUT_SND_A0
L164B:  SHR
L164C:  OUT  OUT_SND_A1
L164D:  SHR
L164E:  OUT  OUT_SND_A2
L164F:  SHR
L1650:  OUT  OUT_SND_STROBE
L1651:  SHR
L1652:  OUT  OUT_SND_STROBE
L1653:  LDAI #$000
L1654:  A8I  #$A0
L1656:  SETP $0
L1657:  STA  TMP03                  ;PRINT: x
L1658:  LDAI #$200
L1659:  A8I  #$58
L165B:  STA  TMP04                  ;PRINT: y
L165C:  LDAI #$000
L165D:  A8I  #$07
L165F:  STA  TMP0E                  ;PRINT: beam-settle delay
L1660:  LDAI #$000
L1661:  A4I  #$3
L1662:  STA  TMP0F                  ;PRINT: 0 = string, 3 = BCD number
L1663:  A8I  #$01
L1665:  STA  TMP02                  ;PRINT: digits to print + 1
L1666:  LDAI #$000
L1667:  A8I  #$6A
L1669:  STA  TMP05                  ;SCORE_HI: three digits at x = $A0, $B8, $D0  PRINT: what to print (string in bank 1 / RAM word)
L166A:  LDAI #$600
L166B:  A8I  #$71
L166D:  STA  RET0                   ;PRINT: return address  return address: L1671
L166E:  LPAI PRINT
L1670:  JMP                         ;call; returns to L1671 via RET0

L1671:  LDAI #$000
L1672:  A8I  #$B8
L1674:  SETP $0
L1675:  STA  TMP03                  ;PRINT: x
L1676:  LDAI #$200
L1677:  A8I  #$58
L1679:  STA  TMP04                  ;PRINT: y
L167A:  LDAI #$000
L167B:  A8I  #$07
L167D:  STA  TMP0E                  ;PRINT: beam-settle delay
L167E:  LDAI #$000
L167F:  A4I  #$3
L1680:  STA  TMP0F                  ;PRINT: 0 = string, 3 = BCD number
L1681:  A8I  #$01
L1683:  STA  TMP02                  ;PRINT: digits to print + 1
L1684:  LDAI #$000
L1685:  A8I  #$6B
L1687:  STA  TMP05                  ;SCORE_LO, printed from one place on ($B8): its leading zeros are spaces, so only its units digit shows, at $E8  PRINT: what to print (string in bank 1 / RAM word)
L1688:  LDAI #$600
L1689:  A8I  #$8F
L168B:  STA  RET0                   ;PRINT: return address  return address: FORMATION
L168C:  LPAI PRINT
L168E:  JMP                         ;call; returns to FORMATION via RET0


;------------------------------------------------------------------------------
; FORMATION - Every few frames the next formation step: the three fighters'
;   positions come from the formation table at FORM_PTR.
;------------------------------------------------------------------------------
FORMATION:
L168F:  LDAI #$000
L1690:  SETP $2
L1691:  LDA  FORM_TIMER
L1692:  LPAI L169A
L1694:  JEQ                         ;not time for the next step  if FORM_TIMER = 0 -> L169A
L1695:  S4I  #$1
L1696:  STAP                        ;store to FORM_TIMER
L1697:  LPAI COINS
L1699:  JMP

L169A:  LDA  FORM_PTR
L169B:  SETP $3
L169C:  STA  FTR1_FORM              ;fighter 1's x, y, z in this step
L169D:  A4I  #$3
L169E:  SETP $4
L169F:  STA  FTR2_FORM              ;fighter 2's (3 bytes on)
L16A0:  A4I  #$3
L16A1:  SETP $5
L16A2:  STA  FTR3_FORM              ;fighter 3's
L16A3:  A4I  #$4
L16A4:  SETP $2
L16A5:  STA  FORM_PTR               ;10 bytes a step
L16A6:  S4I  #$1
L16A7:  LKP                         ;table read $1007-$1FFD
L16A9:  STA  FORM_TIMER             ;the step's time
L16AA:  S8I  #$FF
L16AC:  LPAI L16B3
L16AE:  JCZ                         ;if A < $FF -> L16B3
L16AF:  LDAI #$200
L16B0:  A8I  #$FF
L16B2:  STAP                        ;$FF: the last step, held ($2FF frames)  store to FORM_TIMER
L16B3:  SETP $3
L16B4:  LDA  FTR1_FORM
L16B5:  LKP                         ;table read $1000-$1FFE
L16B7:  SHL
L16B8:  SHL
L16B9:  SHL
L16BA:  SHL
L16BB:  STA  FTR1_DESTX             ;destination = byte x 16
L16BC:  LDA  FTR1_FORM
L16BD:  A4I  #$1
L16BE:  LKP                         ;table read $1001-$1FFF
L16C0:  SHL
L16C1:  SHL
L16C2:  SHL
L16C3:  SHL
L16C4:  STA  FTR1_DESTY
L16C5:  LDA  FTR1_FORM
L16C6:  A4I  #$2
L16C7:  LKP                         ;table read $1000-$1FF6
L16C9:  SHL
L16CA:  SHL
L16CB:  SHL
L16CC:  SHL
L16CD:  STA  FTR1_DESTZ
L16CE:  SETP $4
L16CF:  LDA  FTR2_FORM
L16D0:  LKP                         ;table read $1001-$1FF7
L16D2:  SHL
L16D3:  SHL
L16D4:  SHL
L16D5:  SHL
L16D6:  STA  FTR2_DESTX
L16D7:  LDA  FTR2_FORM
L16D8:  A4I  #$1
L16D9:  LKP                         ;table read $1002-$1FF8
L16DB:  SHL
L16DC:  SHL
L16DD:  SHL
L16DE:  SHL
L16DF:  STA  FTR2_DESTY
L16E0:  LDA  FTR2_FORM
L16E1:  A4I  #$2
L16E2:  LKP                         ;table read $1003-$1FF9
L16E4:  SHL
L16E5:  SHL
L16E6:  SHL
L16E7:  SHL
L16E8:  STA  FTR2_DESTZ
L16E9:  SETP $5
L16EA:  LDA  FTR3_FORM
L16EB:  LKP                         ;table read $1004-$1FFA
L16ED:  SHL
L16EE:  SHL
L16EF:  SHL
L16F0:  SHL
L16F1:  STA  FTR3_DESTX
L16F2:  LDA  FTR3_FORM
L16F3:  A4I  #$1
L16F4:  LKP                         ;table read $1005-$1FFB
L16F6:  SHL
L16F7:  SHL
L16F8:  SHL
L16F9:  SHL
L16FA:  STA  FTR3_DESTY
L16FB:  LDA  FTR3_FORM
L16FC:  A4I  #$2
L16FD:  LKP                         ;table read $1006-$1FFC
L16FF:  SHL
L1700:  SHL
L1701:  SHL
L1702:  SHL
L1703:  STA  FTR3_DESTZ

;------------------------------------------------------------------------------
; COINS - Coins: read the coin latch, reset it, and add a credit (or half of
;   one, with the 2 coins / 1 credit switch).
;------------------------------------------------------------------------------
COINS:
L1704:  SETP $8
L1705:  LDA  CREDITS
L1706:  SETP $7
L1707:  STA  CREDIT_FLAG            ;count the credits in CREDIT_FLAG
L1708:  LDAI #$800
L1709:  SETP $7
L170A:  STA  COIN_SEEN
L170B:  SSA
L170C:  INP  B,SW_COIN              ;B = the coin latch (0: a coin)  switch 7: coin latch: 0 once a coin has dropped, until OUT 5 resets it
L170D:  LDAI #$000
L170E:  A4I  #$1
L170F:  OUT  OUT_COIN_RESET         ;latch input low (a later high clears the coin)
L1710:  SHRB
L1711:  OUT  OUT_COIN_RESET         ;pulse the latch reset  coin latch reset: the rising edge of the latch input (A bit 0 going 1 -> 0) clears it
L1712:  TST  COIN_SEEN              ;A = the latch bit shifted into bit 11: $800 = no coin
L1713:  LPAI L172E
L1715:  JEQ                         ;no coin  if A = COIN_SEEN -> L172E
L1716:  LDAI #$000
L1717:  A4I  #$1
L1718:  STAP                        ;store to COIN_SEEN
L1719:  SSA
L171A:  INP  B,SW_COINAGE           ;switch 0: DIP bit 2: coinage, 1 = 1 coin 1 credit, 0 = 2 coins 1 credit
L171B:  SSA
L171C:  TST  B,COIN_SEEN
L171D:  LPAI L172B
L171F:  JEQ                         ;1 coin 1 credit  if SW_COINAGE = COIN_SEEN -> L172B
;[static] not executed in the traces; reached by following the jumps
L1720:  LDA  HALF_CREDIT
L1721:  A4I  #$1
L1722:  STAP                        ;store to HALF_CREDIT
L1723:  LDAI #$000
L1724:  A4I  #$1
L1725:  TST  HALF_CREDIT
L1726:  LPAI L172E
L1728:  JEQ                         ;the first of two coins  if 1 = HALF_CREDIT -> L172E
L1729:  LDAI #$000
L172A:  STAP                        ;the second: a credit  store to HALF_CREDIT
L172B:  LDA  CREDIT_FLAG
L172C:  A4I  #$1
L172D:  STAP                        ;one more credit  store to CREDIT_FLAG
L172E:  SETP $7
L172F:  LDA  CREDIT_FLAG
L1730:  SETP $8
L1731:  STA  CREDITS                ;CREDITS = the count
L1732:  LDAI #$000
L1733:  SETP $7
L1734:  STA  CREDIT_FLAG            ;CREDIT_FLAG back to 0
HUDGAME:
L1735:  SETP $6
L1736:  TST  FTRS_LEFT
L1737:  LPAI GAMEOVER
L1739:  JEQ                         ;no game: the game-over / attract screens  if FTRS_LEFT = 0 -> GAMEOVER
L173A:  OUT  OUT_INTENSITY          ;dim
L173B:  SETP $8
L173C:  LDA  SHLD_POINTS
L173D:  LPAI L1749
L173F:  JEQ                         ;if SHLD_POINTS = 0 -> L1749
L1740:  S4I  #$A
L1741:  JLT                         ;10 or more points: no blink  if $A < SHLD_POINTS -> L1749
L1742:  LDA  SHLD_BLINK
L1743:  A4I  #$1
L1744:  STAP                        ;store to SHLD_BLINK
L1745:  SHR
L1746:  SHR
L1747:  SHR
L1748:  OUT  OUT_INTENSITY          ;low shields blink (bit 3: every 8 frames)  vector intensity: A bit 0 = 1 bright, 0 dim
L1749:  LDAI #$100
L174A:  A8I  #$CC
L174C:  SETP $0
L174D:  STA  TMP03                  ;PRINT: x
L174E:  LDAI #$200
L174F:  A8I  #$8A
L1751:  STA  TMP04                  ;PRINT: y
L1752:  LDAI #$000
L1753:  A8I  #$21
L1755:  STA  TMP0E                  ;PRINT: beam-settle delay
L1756:  LDAI #$000
L1757:  A4I  #$3
L1758:  STA  TMP0F                  ;PRINT: 0 = string, 3 = BCD number
L1759:  A8I  #$01
L175B:  STA  TMP02                  ;PRINT: digits to print + 1
L175C:  LDAI #$000
L175D:  A8I  #$81
L175F:  STA  TMP05                  ;the shield points, 3 digits, at the top centre  PRINT: what to print (string in bank 1 / RAM word)
L1760:  LDAI #$700
L1761:  A8I  #$67
L1763:  STA  RET0                   ;PRINT: return address  return address: L1767
L1764:  LPAI PRINT
L1766:  JMP                         ;call; returns to L1767 via RET0

L1767:  LDAI #$000
L1768:  SETP $7
L1769:  LDA  PASS_FLASH
L176A:  LPAI L1771
L176C:  JEQ                         ;if PASS_FLASH = 0 -> L1771
L176D:  S4I  #$1
L176E:  STAP                        ;the pass flash counts down  store to PASS_FLASH
L176F:  LDAI #$000
L1770:  A4I  #$1
L1771:  OUT  OUT_INTENSITY          ;bright while it runs  vector intensity: A bit 0 = 1 bright, 0 dim
L1772:  LDAI #$000
L1773:  A4I  #$A
L1774:  SETP $6
L1775:  SUB  FTRS_LEFT
L1776:  STAP                        ;FTRS_LEFT = 10 - FTRS_LEFT: the fighters that got past, for printing  store to FTRS_LEFT
L1777:  S4I  #$9
L1778:  LPAI L1784
L177A:  JCZ                         ;fewer than 9 got past: no blink  if $A - FTRS_LEFT < 9 -> L1784
L177B:  SETP $7
L177C:  LDA  BLINK
L177D:  A4I  #$1
L177E:  STAP                        ;store to BLINK
L177F:  SHR
L1780:  SHR
L1781:  SHR
L1782:  A4I  #$1
L1783:  OUT  OUT_INTENSITY          ;the ninth blinks  vector intensity: A bit 0 = 1 bright, 0 dim
L1784:  LDAI #$300
L1785:  A8I  #$20
L1787:  SETP $0
L1788:  STA  TMP03                  ;PRINT: x
L1789:  LDAI #$200
L178A:  A8I  #$58
L178C:  STA  TMP04                  ;PRINT: y
L178D:  LDAI #$000
L178E:  A8I  #$21
L1790:  STA  TMP0E                  ;PRINT: beam-settle delay
L1791:  LDAI #$000
L1792:  A4I  #$3
L1793:  STA  TMP0F                  ;PRINT: 0 = string, 3 = BCD number
L1794:  A8I  #$01
L1796:  STA  TMP02                  ;PRINT: digits to print + 1
L1797:  LDAI #$000
L1798:  A8I  #$69
L179A:  STA  TMP05                  ;at the top right  PRINT: what to print (string in bank 1 / RAM word)
L179B:  LDAI #$700
L179C:  A8I  #$A2
L179E:  STA  RET0                   ;PRINT: return address  return address: L17A2
L179F:  LPAI PRINT
L17A1:  JMP                         ;call; returns to L17A2 via RET0

L17A2:  LDAI #$000
L17A3:  A4I  #$A
L17A4:  SETP $6
L17A5:  SUB  FTRS_LEFT
L17A6:  STAP                        ;FTRS_LEFT back  store to FTRS_LEFT
L17A7:  LDAI #$000
L17A8:  A8I  #$1D
L17AA:  OUT  OUT_SND_DATA           ;the game's background rumble  sound: rumble on
L17AB:  SHR
L17AC:  OUT  OUT_SND_A0
L17AD:  SHR
L17AE:  OUT  OUT_SND_A1
L17AF:  SHR
L17B0:  OUT  OUT_SND_A2
L17B1:  SHR
L17B2:  OUT  OUT_SND_STROBE
L17B3:  SHR
L17B4:  OUT  OUT_SND_STROBE
L17B5:  LPAI MAINLOOP               ;T4K to bank 0
L17B7:  SETP $1
L17B8:  T4K                         ;next frame


;------------------------------------------------------------------------------
; GAMEOVER - Game over: keep a new high score, end the shot and the sounds,
;   show the title.
;------------------------------------------------------------------------------
GAMEOVER:
L17B9:  SETP $6
L17BA:  LDA  SCORE_HI
L17BB:  TST  HISCORE_HI
L17BC:  LPAI L17CB
L17BE:  JCZ                         ;lower: no new high score  if SCORE_HI < HISCORE_HI -> L17CB
L17BF:  LPAI L17C5
L17C1:  JEQ                         ;equal: compare the units  if SCORE_HI = HISCORE_HI -> L17C5
L17C2:  STAP                        ;higher: the new high score  store to HISCORE_HI
L17C3:  LDA  SCORE_LO
L17C4:  STA  HISCORE_LO
L17C5:  LDA  SCORE_LO
L17C6:  TST  HISCORE_LO
L17C7:  LPAI L17CB
L17C9:  JCZ                         ;if SCORE_LO < HISCORE_LO -> L17CB
L17CA:  STAP                        ;higher units  store to HISCORE_LO
L17CB:  JVN                         ;while the vector generator is busy -> L17CB
L17CC:  SSA
L17CD:  LDAI B,#$200
L17CE:  SSA
L17CF:  A8I  B,#$76
L17D1:  LDAI #$200
L17D2:  A8I  #$DA
L17D4:  IV                          ;beam to ($2DA, $276)
L17D5:  LDAI #$000
L17D6:  OUT  OUT_INTENSITY          ;dim
L17D7:  A4I  #$1
L17D8:  SETP $6
L17D9:  STA  FIRE_LAST              ;fire counts as released
L17DA:  LDAI #$000
L17DB:  STA  SHOT                   ;no shot
L17DC:  STA  FIRE_WAIT
L17DD:  LDAI #$000
L17DE:  A8I  #$1C
L17E0:  OUT  OUT_SND_DATA           ;sound: rumble off
L17E1:  SHR
L17E2:  OUT  OUT_SND_A0
L17E3:  SHR
L17E4:  OUT  OUT_SND_A1
L17E5:  SHR
L17E6:  OUT  OUT_SND_A2
L17E7:  SHR
L17E8:  OUT  OUT_SND_STROBE
L17E9:  SHR
L17EA:  OUT  OUT_SND_STROBE
L17EB:  LDAI #$200
L17EC:  A8I  #$BC
L17EE:  SETP $0
L17EF:  STA  TMP03                  ;PRINT: x
L17F0:  LDAI #$200
L17F1:  A8I  #$8A
L17F3:  STA  TMP04                  ;PRINT: y
L17F4:  LDAI #$000
L17F5:  A8I  #$21
L17F7:  STA  TMP0E                  ;PRINT: beam-settle delay
L17F8:  LDAI #$000
L17F9:  STA  TMP0F                  ;PRINT: 0 = string, 3 = BCD number
L17FA:  LDAI #$800
L17FB:  A8I  #$03
L17FD:  STA  TMP05                  ;PRINT: what to print (string in bank 1 / RAM word)
L17FE:  A8I  #$0C                   ;the string $1804; PRINT returns past it, to HUDHISCORE
L1800:  STA  RET0                   ;PRINT: return address
L1801:  LPAI PRINT
L1803:  JMP

;$1804-$180E, read by LKP at L1B11
TXT_HISCORE:
L1804:  .byte $48, $49, $47, $48, $5B, $53, $43, $4F, $52, $45, $FF  ;"HIGH SCORE", $FF

;------------------------------------------------------------------------------
; HUDHISCORE - The high score: HISCORE_HI / HISCORE_LO printed under HIGH
;   SCORE.
;   Reached by the jump through RAM at L1B6D.
;------------------------------------------------------------------------------
HUDHISCORE:
L180F:  LDAI #$200
L1810:  A8I  #$F8
L1812:  SETP $0
L1813:  STA  TMP03                  ;PRINT: x
L1814:  LDAI #$200
L1815:  A8I  #$58
L1817:  STA  TMP04                  ;PRINT: y
L1818:  LDAI #$000
L1819:  A8I  #$07
L181B:  STA  TMP0E                  ;PRINT: beam-settle delay
L181C:  LDAI #$000
L181D:  A4I  #$3
L181E:  STA  TMP0F                  ;PRINT: 0 = string, 3 = BCD number
L181F:  A8I  #$01
L1821:  STA  TMP02                  ;PRINT: digits to print + 1
L1822:  LDAI #$000
L1823:  A8I  #$6C                   ;HISCORE_HI at x = $2F8
L1825:  STA  TMP05                  ;PRINT: what to print (string in bank 1 / RAM word)
L1826:  LDAI #$800
L1827:  A8I  #$2D
L1829:  STA  RET0                   ;PRINT: return address  return address: L182D
L182A:  LPAI PRINT
L182C:  JMP                         ;call; returns to L182D via RET0

L182D:  LDAI #$300
L182E:  A8I  #$10
L1830:  SETP $0
L1831:  STA  TMP03                  ;PRINT: x
L1832:  LDAI #$200
L1833:  A8I  #$58
L1835:  STA  TMP04                  ;PRINT: y
L1836:  LDAI #$000
L1837:  A8I  #$07
L1839:  STA  TMP0E                  ;PRINT: beam-settle delay
L183A:  LDAI #$000
L183B:  A4I  #$3
L183C:  STA  TMP0F                  ;PRINT: 0 = string, 3 = BCD number
L183D:  A8I  #$01
L183F:  STA  TMP02                  ;PRINT: digits to print + 1
L1840:  LDAI #$000
L1841:  A8I  #$6D                   ;HISCORE_LO one place on, units only (as HUDSCORE)
L1843:  STA  TMP05                  ;PRINT: what to print (string in bank 1 / RAM word)
L1844:  LDAI #$800
L1845:  A8I  #$4B
L1847:  STA  RET0                   ;PRINT: return address  return address: HUDCREDITS
L1848:  LPAI PRINT
L184A:  JMP                         ;call; returns to HUDCREDITS via RET0

HUDCREDITS:
L184B:  LDAI #$000
L184C:  SETP $8
L184D:  TST  CREDITS
L184E:  LPAI ATTRACT
L1850:  JEQ                         ;no credit: the attract title  if CREDITS = 0 -> ATTRACT
L1851:  LDAI #$000
L1852:  OUT  OUT_INTENSITY          ;dim
L1853:  A4I  #$1
L1854:  SETP $7
L1855:  STA  CREDIT_FLAG            ;the credit screen is up
L1856:  CST                         ;CST: clear the watchdog  CREDIT_FLAG
L1857:  LDAI #$100
L1858:  A8I  #$90
L185A:  SETP $0
L185B:  STA  TMP03                  ;PRINT: x
L185C:  LDAI #$000
L185D:  A8I  #$32
L185F:  STA  TMP04                  ;PRINT: y
L1860:  LDAI #$000
L1861:  A8I  #$4D
L1863:  STA  TMP0E                  ;PRINT: beam-settle delay
L1864:  LDAI #$000
L1865:  STA  TMP0F                  ;PRINT: 0 = string, 3 = BCD number
L1866:  LDAI #$800
L1867:  A8I  #$6F
L1869:  STA  TMP05                  ;PRINT: what to print (string in bank 1 / RAM word)
L186A:  A8I  #$09                   ;the string $1870; PRINT returns past it, to SHOWCREDITS
L186C:  STA  RET0                   ;PRINT: return address
L186D:  LPAI PRINT
L186F:  JMP

;$1870-$1877, read by LKP at L1B11
TXT_CREDITS:
L1870:  .byte $43, $52, $45, $44, $49, $54, $53, $FF  ;"CREDITS", $FF

;------------------------------------------------------------------------------
; SHOWCREDITS - Credits on the attract screen (at most 9 shown), every sound
;   off, PUSH START blinking (BLINK).
;   Reached by the jump through RAM at L1B6D.
;------------------------------------------------------------------------------
SHOWCREDITS:
L1878:  SETP $8
L1879:  LDA  CREDITS
L187A:  STA  CREDITS_SHOWN
L187B:  S4I  #$9
L187C:  LPAI L1882
L187E:  JCZ                         ;if CREDITS < 9 -> L1882
;[static] not executed in the traces; reached by following the jumps
L187F:  LDAI #$000
L1880:  A4I  #$9
L1881:  STAP                        ;at most 9 shown  store to CREDITS_SHOWN
L1882:  LDAI #$200
L1883:  A8I  #$58
L1885:  SETP $0
L1886:  STA  TMP03                  ;PRINT: x
L1887:  LDAI #$000
L1888:  A8I  #$32
L188A:  STA  TMP04                  ;PRINT: y
L188B:  LDAI #$000
L188C:  A8I  #$0B
L188E:  STA  TMP0E                  ;PRINT: beam-settle delay
L188F:  LDAI #$000
L1890:  A4I  #$3
L1891:  STA  TMP0F                  ;PRINT: 0 = string, 3 = BCD number
L1892:  A8I  #$01
L1894:  STA  TMP02                  ;PRINT: digits to print + 1
L1895:  LDAI #$000
L1896:  A8I  #$8C
L1898:  STA  TMP05                  ;PRINT: what to print (string in bank 1 / RAM word)
L1899:  LDAI #$800
L189A:  A8I  #$A0
L189C:  STA  RET0                   ;PRINT: return address  return address: L18A0
L189D:  LPAI PRINT
L189F:  JMP                         ;call; returns to L18A0 via RET0

L18A0:  LDAI #$000
L18A1:  A8I  #$1E
L18A3:  OUT  OUT_SND_DATA           ;sound: explosion off
L18A4:  SHR
L18A5:  OUT  OUT_SND_A0
L18A6:  SHR
L18A7:  OUT  OUT_SND_A1
L18A8:  SHR
L18A9:  OUT  OUT_SND_A2
L18AA:  SHR
L18AB:  OUT  OUT_SND_STROBE
L18AC:  SHR
L18AD:  OUT  OUT_SND_STROBE
L18AE:  LDAI #$000
L18AF:  A8I  #$1A
L18B1:  OUT  OUT_SND_DATA           ;sound: laser off
L18B2:  SHR
L18B3:  OUT  OUT_SND_A0
L18B4:  SHR
L18B5:  OUT  OUT_SND_A1
L18B6:  SHR
L18B7:  OUT  OUT_SND_A2
L18B8:  SHR
L18B9:  OUT  OUT_SND_STROBE
L18BA:  SHR
L18BB:  OUT  OUT_SND_STROBE
L18BC:  LDAI #$000
L18BD:  A8I  #$14
L18BF:  OUT  OUT_SND_DATA           ;sound: hyperspace off
L18C0:  SHR
L18C1:  OUT  OUT_SND_A0
L18C2:  SHR
L18C3:  OUT  OUT_SND_A1
L18C4:  SHR
L18C5:  OUT  OUT_SND_A2
L18C6:  SHR
L18C7:  OUT  OUT_SND_STROBE
L18C8:  SHR
L18C9:  OUT  OUT_SND_STROBE
L18CA:  LDAI #$000
L18CB:  A8I  #$16
L18CD:  OUT  OUT_SND_DATA           ;sound: bounce off
L18CE:  SHR
L18CF:  OUT  OUT_SND_A0
L18D0:  SHR
L18D1:  OUT  OUT_SND_A1
L18D2:  SHR
L18D3:  OUT  OUT_SND_A2
L18D4:  SHR
L18D5:  OUT  OUT_SND_STROBE
L18D6:  SHR
L18D7:  OUT  OUT_SND_STROBE
L18D8:  LDAI #$000
L18D9:  A8I  #$18
L18DB:  OUT  OUT_SND_DATA           ;sound: shield off
L18DC:  SHR
L18DD:  OUT  OUT_SND_A0
L18DE:  SHR
L18DF:  OUT  OUT_SND_A1
L18E0:  SHR
L18E1:  OUT  OUT_SND_A2
L18E2:  SHR
L18E3:  OUT  OUT_SND_STROBE
L18E4:  SHR
L18E5:  OUT  OUT_SND_STROBE
L18E6:  SETP $7
L18E7:  LDA  BLINK
L18E8:  A4I  #$1
L18E9:  STAP                        ;store to BLINK
L18EA:  LDAI #$000
L18EB:  A4I  #$8
L18EC:  ANDP                        ;bit 3 of BLINK: every 8 frames  BLINK
L18ED:  SHR
L18EE:  SHR
L18EF:  SHR
L18F0:  OUT  OUT_INTENSITY          ;PUSH START blinks  vector intensity: A bit 0 = 1 bright, 0 dim
L18F1:  A8I  #$12
L18F3:  OUT  OUT_SND_DATA           ;sound bit 6 follows the blink  sound: bit 6 on or off (bit 0 of A)
L18F4:  SHR
L18F5:  OUT  OUT_SND_A0
L18F6:  SHR
L18F7:  OUT  OUT_SND_A1
L18F8:  SHR
L18F9:  OUT  OUT_SND_A2
L18FA:  SHR
L18FB:  OUT  OUT_SND_STROBE
L18FC:  SHR
L18FD:  OUT  OUT_SND_STROBE
L18FE:  CST                         ;CST: clear the watchdog  BLINK
L18FF:  LDAI #$100
L1900:  A8I  #$90
L1902:  SETP $0
L1903:  STA  TMP03                  ;PRINT: x
L1904:  LDAI #$100
L1905:  A8I  #$90
L1907:  STA  TMP04                  ;PRINT: y
L1908:  LDAI #$000
L1909:  A8I  #$2C
L190B:  STA  TMP0E                  ;PRINT: beam-settle delay
L190C:  LDAI #$000
L190D:  STA  TMP0F                  ;PRINT: 0 = string, 3 = BCD number
L190E:  LDAI #$900
L190F:  A8I  #$17
L1911:  STA  TMP05                  ;PRINT: what to print (string in bank 1 / RAM word)
L1912:  A8I  #$0C                   ;the string $1918; PRINT returns past it, to WAITSTART
L1914:  STA  RET0                   ;PRINT: return address
L1915:  LPAI PRINT
L1917:  JMP

;$1918-$1922, read by LKP at L1B11
TXT_PUSHSTART:
L1918:  .byte $50, $55, $53, $48, $5B, $53, $54, $41, $52, $54, $FF  ;"PUSH START", $FF

;------------------------------------------------------------------------------
; WAITSTART - With a credit: wait for START; start a game (credits - 1, score
;   and fighters cleared, shields from the DIP setting, 10 fighters to stop).
;   Reached by the jump through RAM at L1B6D.
;------------------------------------------------------------------------------
WAITSTART:
L1923:  INP  IN_START               ;input 7: start button (active low)
L1924:  A4I  #$1
L1925:  LPAI TOMAIN
L1927:  JEQ                         ;if IN_START = 1 (not pressed) -> TOMAIN
L1928:  SETP $8
L1929:  LDA  CREDITS
L192A:  S4I  #$1
L192B:  STAP                        ;one credit used  store to CREDITS
L192C:  LDAI #$000
L192D:  A8I  #$12
L192F:  OUT  OUT_SND_DATA           ;sound: bit 6 off
L1930:  SHR
L1931:  OUT  OUT_SND_A0
L1932:  SHR
L1933:  OUT  OUT_SND_A1
L1934:  SHR
L1935:  OUT  OUT_SND_A2
L1936:  SHR
L1937:  OUT  OUT_SND_STROBE
L1938:  SHR
L1939:  OUT  OUT_SND_STROBE
L193A:  LDAI #$000
L193B:  SETP $2
L193C:  STA  STICK_X
L193D:  STA  STICK_Y
L193E:  SETP $7
L193F:  STA  CREDIT_FLAG
L1940:  STA  TITLE_STATE            ;no title, no credit screen
L1941:  SETP $6
L1942:  STA  SCORE_HI
L1943:  STA  SCORE_LO               ;score 0
L1944:  SETP $3
L1945:  STA  FTR1_MODEL
L1946:  SETP $4
L1947:  STA  FTR2_MODEL
L1948:  SETP $5
L1949:  STA  FTR3_MODEL             ;no fighters: the first pass starts a wave
L194A:  SETP $7
L194B:  STA  BLINK
L194C:  SETP $8
L194D:  STA  SHLD_FRAMES
L194E:  LDA  SHLD_START
L194F:  STA  SHLD_POINTS            ;shields from the DIP setting
L1950:  LDAI #$000
L1951:  A4I  #$A
L1952:  SETP $6
L1953:  STA  FTRS_LEFT              ;10 fighters may get past
L1954:  SETP $8
L1955:  LDA  GAMES
L1956:  A4I  #$1
L1957:  STAP                        ;one more game  store to GAMES
L1958:  LPAI MAINLOOP               ;T4K to bank 0
L195A:  SETP $1
L195B:  T4K


;------------------------------------------------------------------------------
; ATTRACT - Attract mode: the title sequence (TITLE_STATE) - the 3D 'TAIL
;   GUNNER' letters fly in and turn.
;------------------------------------------------------------------------------
ATTRACT:
L195C:  LDAI #$000
L195D:  A8I  #$12
L195F:  OUT  OUT_SND_DATA           ;sound: bit 6 off
L1960:  SHR
L1961:  OUT  OUT_SND_A0
L1962:  SHR
L1963:  OUT  OUT_SND_A1
L1964:  SHR
L1965:  OUT  OUT_SND_A2
L1966:  SHR
L1967:  OUT  OUT_SND_STROBE
L1968:  SHR
L1969:  OUT  OUT_SND_STROBE
L196A:  LDAI #$000
L196B:  SETP $7
L196C:  LDA  TITLE_STATE
L196D:  LPAI TOMAIN
L196F:  JEQ                         ;the title sequence is not running  if TITLE_STATE = 0 -> TOMAIN
L1970:  SHR
L1971:  SHR
L1972:  OUT  OUT_INTENSITY          ;vector intensity: A bit 0 = 1 bright, 0 dim
L1973:  LDAI #$000
L1974:  SETP $1
L1975:  STA  OBJ_PTR                ;OBJ_PTR = 0: no explosion
L1976:  STA  OBJ_X
L1977:  STA  OBJ_Y
L1978:  STA  TMP1C
L1979:  A8I  #$FF
L197B:  STA  TMP1D                  ;angle 1 fixed: sine 0, cosine $FF
L197C:  LDAI #$000
L197D:  A4I  #$2
L197E:  SETP $7
L197F:  TST  TITLE_STATE
L1980:  LPAI L19B2
L1982:  JCZ                         ;past the fly-in: count on  if 2 < TITLE_STATE -> L19B2
L1983:  LDA  TITLE_ANGLE
L1984:  S4I  #$3
L1985:  STAP                        ;turn 3 a frame  store to TITLE_ANGLE
L1986:  SETP $1
L1987:  STA  TMP1E                  ;SINCOS1: angle
L1988:  LDAI #$900
L1989:  A8I  #$8F
L198B:  STA  RET1                   ;SINCOS1: return address  return address: L198F
L198C:  LPAI SINCOS1
L198E:  JMP                         ;call; returns to L198F via RET1

L198F:  LDAI #$200
L1990:  SETP $7
L1991:  TST  TITLE_Z
L1992:  LPAI L1998
L1994:  JCZ                         ;still far: keep flying in  if $200 < TITLE_Z -> L1998
L1995:  LDAI #$000
L1996:  A4I  #$3
L1997:  STA  TITLE_STATE            ;arrived: state 3
L1998:  LDA  TITLE_Z
L1999:  S4I  #$B
L199A:  STAP                        ;nearer by $B a frame  store to TITLE_Z
L199B:  SETP $1
L199C:  STA  OBJ_Z

;------------------------------------------------------------------------------
; TITLESTEP - Title sequence, after SINCOS1: beam to the title position, then
;   TITLE3D.
;   Reached by the jump through RAM at L15D5.
;------------------------------------------------------------------------------
TITLESTEP:
L199D:  LDAI #$900
L199E:  A8I  #$C3
L19A0:  SETP $0
L19A1:  STA  RET0                   ;TITLE3D returns to TOMAIN
L19A2:  SSA
L19A3:  LDAI B,#$300
L19A4:  SHRB
L19A5:  SSA
L19A6:  A8I  B,#$32
L19A8:  LDAI #$200
L19A9:  S8I  #$32
L19AB:  LPAI L19AD
L19AD:  JVN                         ;while the vector generator is busy -> L19AD
L19AE:  IV                          ;beam to the title's centre
L19AF:  LPAI TITLE3D
L19B1:  JMP

L19B2:  LDAP
L19B3:  A4I  #$1
L19B4:  STAP                        ;TITLE_STATE + 1 (it ends at $1F, L02B6)
L19B5:  LDA  TITLE_Z
L19B6:  SETP $1
L19B7:  STA  OBJ_Z
L19B8:  SETP $7
L19B9:  LDA  TITLE_ANGLE
L19BA:  SETP $1
L19BB:  STA  TMP1E                  ;SINCOS1: angle
L19BC:  LDAI #$900
L19BD:  A8I  #$9D
L19BF:  STA  RET1                   ;SINCOS1: return address
L19C0:  LPAI SINCOS1
L19C2:  JMP


;------------------------------------------------------------------------------
; TOMAIN - Back to MAINLOOP in bank 0 (T4K with P=1).
;   Reached by the jump through RAM at L1480.
;------------------------------------------------------------------------------
TOMAIN:
L19C3:  LPAI MAINLOOP               ;T4K to bank 0
L19C5:  SETP $1
L19C6:  T4K


;------------------------------------------------------------------------------
; TITLE3D - Draw the 3D title letters (DRAWMODEL3D with the letter models at
;   LETTERS).
;------------------------------------------------------------------------------
TITLE3D:
L19C7:  LDAI #$A00
L19C8:  A8I  #$1B
L19CA:  SETP $1
L19CB:  STA  TMP16                  ;DRAWMODEL3D: vertex list
L19CC:  A8I  #$1A
L19CE:  STA  TMP17                  ;Letters 1: the frame, always drawn  DRAWMODEL3D: edge list
L19CF:  LDAI #$900
L19D0:  A8I  #$D7
L19D2:  SETP $2
L19D3:  STA  RET2                   ;DRAWMODEL3D: return address  return address: L19D7
L19D4:  LPAI DRAWMODEL3D
L19D6:  JMP                         ;call; returns to L19D7 via RET2

L19D7:  LDAI #$000
L19D8:  A8I  #$7F
L19DA:  SETP $7
L19DB:  TST  TITLE_ANGLE
L19DC:  ANDP                        ;TITLE_ANGLE
L19DD:  STAP                        ;store to TITLE_ANGLE
L19DE:  S8I  #$20
L19E0:  LPAI L19EB
L19E2:  JCZ                         ;facing the front (within 90 degrees): the letters too  if TITLE_ANGLE & $7F < $20 -> L19EB
L19E3:  LDAI #$000
L19E4:  A8I  #$60
L19E6:  TST  TITLE_ANGLE
L19E7:  JCZ                         ;if $60 < TITLE_ANGLE -> L19EB
L19E8:  LPAI DRAWFTRSRET
L19EA:  JMP                         ;turned away: only the frame

L19EB:  LDAI #$A00
L19EC:  A8I  #$3E
L19EE:  SETP $1
L19EF:  STA  TMP16                  ;DRAWMODEL3D: vertex list
L19F0:  A8I  #$32
L19F2:  STA  TMP17                  ;Letters 2  DRAWMODEL3D: edge list
L19F3:  LDAI #$900
L19F4:  A8I  #$FB
L19F6:  SETP $2
L19F7:  STA  RET2                   ;DRAWMODEL3D: return address  return address: L19FB
L19F8:  LPAI DRAWMODEL3D
L19FA:  JMP                         ;call; returns to L19FB via RET2

L19FB:  LDAI #$A00
L19FC:  A8I  #$7A
L19FE:  SETP $1
L19FF:  STA  TMP16                  ;DRAWMODEL3D: vertex list
L1A00:  A8I  #$32
L1A02:  STA  TMP17                  ;Letters 3  DRAWMODEL3D: edge list
L1A03:  LDAI #$A00
L1A04:  A8I  #$0B
L1A06:  SETP $2
L1A07:  STA  RET2                   ;DRAWMODEL3D: return address  return address: L1A0B
L1A08:  LPAI DRAWMODEL3D
L1A0A:  JMP                         ;call; returns to L1A0B via RET2

L1A0B:  LDAI #$A00
L1A0C:  A8I  #$B8
L1A0E:  SETP $1
L1A0F:  STA  TMP16                  ;DRAWMODEL3D: vertex list
L1A10:  A8I  #$2F
L1A12:  STA  TMP17                  ;Letters 4  DRAWMODEL3D: edge list
L1A13:  LDAI #$400
L1A14:  A8I  #$7D
L1A16:  SETP $2
L1A17:  STA  RET2                   ;DRAWMODEL3D: return address
L1A18:  LPAI DRAWMODEL3D
L1A1A:  JMP

;$1A1B-$1AF2, read by LKP at L113E, L114B, L1154, L139E
LETTERS:
LETTERS1:
L1A1B:  .byte $47, $9B, $80         ;vertex  0: x  -57  y  +27  z   +0
L1A1E:  .byte $B9, $9B, $80         ;vertex  1: x  +57  y  +27  z   +0
L1A21:  .byte $B9, $65, $80         ;vertex  2: x  +57  y  -27  z   +0
L1A24:  .byte $47, $65, $80         ;vertex  3: x  -57  y  -27  z   +0
L1A27:  .byte $3F, $A3, $80         ;vertex  4: x  -65  y  +35  z   +0
L1A2A:  .byte $C1, $A3, $80         ;vertex  5: x  +65  y  +35  z   +0
L1A2D:  .byte $C1, $5D, $80         ;vertex  6: x  +65  y  -35  z   +0
L1A30:  .byte $3F, $5D, $80         ;vertex  7: x  -65  y  -35  z   +0
L1A33:  .byte $FF                   ;end of vertices
L1A34:  .byte $FF
LETTERS1_EDGES:
L1A35:  .byte $01, $12, $23, $30, $45, $56, $67, $74  ;edges 0-1 1-2 2-3 3-0 4-5 5-6 6-7 7-4
L1A3D:  .byte $FF                   ;end of edges
LETTERS2:
L1A3E:  .byte $5D, $95, $80         ;vertex  0: x  -35  y  +21  z   +0
L1A41:  .byte $6D, $95, $80         ;vertex  1: x  -19  y  +21  z   +0
L1A44:  .byte $65, $95, $80         ;vertex  2: x  -27  y  +21  z   +0
L1A47:  .byte $65, $83, $80         ;vertex  3: x  -27  y   +3  z   +0
L1A4A:  .byte $71, $83, $80         ;vertex  4: x  -15  y   +3  z   +0
L1A4D:  .byte $77, $95, $80         ;vertex  5: x   -9  y  +21  z   +0
L1A50:  .byte $7D, $83, $80         ;vertex  6: x   -3  y   +3  z   +0
L1A53:  .byte $74, $8C, $80         ;vertex  7: x  -12  y  +12  z   +0
L1A56:  .byte $7A, $8C, $80         ;vertex  8: x   -6  y  +12  z   +0
L1A59:  .byte $89, $83, $80         ;vertex  9: x   +9  y   +3  z   +0
L1A5C:  .byte $89, $95, $80         ;vertex 10: x   +9  y  +21  z   +0
L1A5F:  .byte $95, $95, $80         ;vertex 11: x  +21  y  +21  z   +0
L1A62:  .byte $95, $83, $80         ;vertex 12: x  +21  y   +3  z   +0
L1A65:  .byte $A1, $83, $80         ;vertex 13: x  +33  y   +3  z   +0
L1A68:  .byte $A7, $7D, $80         ;vertex 14: x  +39  y   -3  z   +0
L1A6B:  .byte $A7, $6B, $80         ;vertex 15: x  +39  y  -21  z   +0
L1A6E:  .byte $FF                   ;end of vertices
L1A6F:  .byte $FF
LETTERS2_EDGES:
L1A70:  .byte $01, $23, $45, $56, $78, $9A, $BC, $CD  ;edges 0-1 2-3 4-5 5-6 7-8 9-10 11-12 12-13
L1A78:  .byte $EF                   ;edges 14-15
L1A79:  .byte $FF                   ;end of edges
LETTERS3:
L1A7A:  .byte $A7, $7D, $80         ;vertex  0: x  +39  y   -3  z   +0
L1A7D:  .byte $B3, $7D, $80         ;vertex  1: x  +51  y   -3  z   +0
L1A80:  .byte $B3, $74, $80         ;vertex  2: x  +51  y  -12  z   +0
L1A83:  .byte $B0, $74, $80         ;vertex  3: x  +48  y  -12  z   +0
L1A86:  .byte $B3, $6B, $80         ;vertex  4: x  +51  y  -21  z   +0
L1A89:  .byte $A7, $74, $80         ;vertex  5: x  +39  y  -12  z   +0
L1A8C:  .byte $A1, $6B, $80         ;vertex  6: x  +33  y  -21  z   +0
L1A8F:  .byte $95, $6B, $80         ;vertex  7: x  +21  y  -21  z   +0
L1A92:  .byte $95, $7D, $80         ;vertex  8: x  +21  y   -3  z   +0
L1A95:  .byte $A1, $7D, $80         ;vertex  9: x  +33  y   -3  z   +0
L1A98:  .byte $9B, $74, $80         ;vertex 10: x  +27  y  -12  z   +0
L1A9B:  .byte $95, $74, $80         ;vertex 11: x  +21  y  -12  z   +0
L1A9E:  .byte $8F, $7D, $80         ;vertex 12: x  +15  y   -3  z   +0
L1AA1:  .byte $8F, $6B, $80         ;vertex 13: x  +15  y  -21  z   +0
L1AA4:  .byte $83, $7D, $80         ;vertex 14: x   +3  y   -3  z   +0
L1AA7:  .byte $83, $6B, $80         ;vertex 15: x   +3  y  -21  z   +0
L1AAA:  .byte $FF                   ;end of vertices
L1AAB:  .byte $FF
LETTERS3_EDGES:
L1AAC:  .byte $01, $12, $34, $25, $67, $78, $89, $AB  ;edges 0-1 1-2 3-4 2-5 6-7 7-8 8-9 10-11
L1AB4:  .byte $CD, $DE, $EF         ;edges 12-13 13-14 14-15
L1AB7:  .byte $FF                   ;end of edges
LETTERS4:
L1AB8:  .byte $7D, $7D, $80         ;vertex  0: x   -3  y   -3  z   +0
L1ABB:  .byte $7D, $6B, $80         ;vertex  1: x   -3  y  -21  z   +0
L1ABE:  .byte $71, $7D, $80         ;vertex  2: x  -15  y   -3  z   +0
L1AC1:  .byte $71, $6B, $80         ;vertex  3: x  -15  y  -21  z   +0
L1AC4:  .byte $6B, $7D, $80         ;vertex  4: x  -21  y   -3  z   +0
L1AC7:  .byte $6B, $6B, $80         ;vertex  5: x  -21  y  -21  z   +0
L1ACA:  .byte $5F, $6B, $80         ;vertex  6: x  -33  y  -21  z   +0
L1ACD:  .byte $5F, $7D, $80         ;vertex  7: x  -33  y   -3  z   +0
L1AD0:  .byte $5C, $72, $80         ;vertex  8: x  -36  y  -14  z   +0
L1AD3:  .byte $56, $72, $80         ;vertex  9: x  -42  y  -14  z   +0
L1AD6:  .byte $59, $72, $80         ;vertex 10: x  -39  y  -14  z   +0
L1AD9:  .byte $59, $6B, $80         ;vertex 11: x  -39  y  -21  z   +0
L1ADC:  .byte $4D, $6B, $80         ;vertex 12: x  -51  y  -21  z   +0
L1ADF:  .byte $4D, $7D, $80         ;vertex 13: x  -51  y   -3  z   +0
L1AE2:  .byte $59, $7D, $80         ;vertex 14: x  -39  y   -3  z   +0
L1AE5:  .byte $FF                   ;end of vertices
L1AE6:  .byte $FF
LETTERS4_EDGES:
L1AE7:  .byte $01, $12, $23, $45, $56, $67, $89, $AB  ;edges 0-1 1-2 2-3 4-5 5-6 6-7 8-9 10-11
L1AEF:  .byte $BC, $CD, $DE         ;edges 11-12 12-13 13-14
L1AF2:  .byte $FF                   ;end of edges

;------------------------------------------------------------------------------
; PRINT - Print a string or a BCD number with the vector font, characters 24
;   apart ($18). TMP03 / TMP04 = x, y of the first; TMP0E = a beam-settle delay
;   before drawing. TMP0F = 0: the ASCII string at bank 1 address TMP05 + 1,
;   ended by $FF. Otherwise TMP0F = 3 and TMP02 = digits + 1: BCD digits from
;   the RAM word at TMP05, three per 12-bit word, high digit first, going on to
;   the next word; leading zeros print as spaces, the last digit always prints.
;   Returns through RET0.
;   Called from L1670, L168E, L1766, L17A1, L182C, L184A, L189F (return address
;   in RET0).
;------------------------------------------------------------------------------
PRINT:
L1AF3:  LDA  TMP03
L1AF4:  SSA
L1AF5:  LDA  B,TMP04
L1AF6:  LPAI L1AF6
L1AF8:  JVN                         ;while the vector generator is busy -> L1AF6
L1AF9:  IV                          ;beam to x, y
L1AFA:  LDAI #$000
L1AFB:  SUB  TMP0E
L1AFC:  S4I  #$1
L1AFD:  A4I  #$1
L1AFE:  LPAI L1AFD
L1B00:  JCZ                         ;a delay of TMP0E + 1 loops  until A + 1 carries (reaches $1000) -> L1AFD
L1B01:  STA  TMP0E                  ;TMP0E = 0: no digit printed yet
L1B02:  A8I  #$18
L1B04:  STA  TMP06                  ;characters $18 apart
L1B05:  LDAI #$000
L1B06:  A8I  #$FF
L1B08:  STA  TMP01                  ;$FF ends a string
L1B09:  LDAI #$000
L1B0A:  TST  TMP0F
L1B0B:  LPAI L1B21
L1B0D:  JCZ                         ;TMP0F set: a number  if TMP0F > 0 -> L1B21
L1B0E:  LDA  TMP05
L1B0F:  A4I  #$1
L1B10:  STAP                        ;the next character's address  store to TMP05
L1B11:  LKP                         ;next character of the string  table read $1634-$1922
L1B13:  STA  TMP07
L1B14:  TST  TMP01
L1B15:  LPAI PRINTRET
L1B17:  JEQ                         ;the end of the string  if A = TMP01 -> PRINTRET
L1B18:  S8I  #$40
L1B1A:  LPAI PRINTCHR
L1B1C:  JCZ                         ;below $40 ('0'-'9' and the rest): the code as it is  if A < $40 -> PRINTCHR
L1B1D:  A8I  #$39
L1B1F:  STA  TMP07                  ;letters: code - 7, so 'A' follows '9'
L1B20:  JMP

L1B21:  LDA  TMP02
L1B22:  S4I  #$1
L1B23:  LPAI PRINTRET
L1B25:  JEQ                         ;all the digits printed  if TMP02 = 1 -> PRINTRET
L1B26:  STAP                        ;one digit fewer to go  store to TMP02
L1B27:  WS   TMP05                  ;I = the address in TMP05
L1B28:  LDAP                        ;the BCD word  [TMP05]
L1B29:  STA  TMP07
L1B2A:  LDA  TMP0F
L1B2B:  S4I  #$1                    ;TMP0F: the digit's place in the word, 3, 2, 1
L1B2C:  STAP                        ;store to TMP0F
L1B2D:  LPAI L1B63
L1B2F:  JEQ                         ;if TMP0F = 1 -> L1B63
L1B30:  S4I  #$1
L1B31:  LPAI L1B3C
L1B33:  JEQ                         ;the middle digit  if TMP0F-1 = 1 -> L1B3C
L1B34:  LDA  TMP07                  ;the high digit: >> 4 here and >> 4 at L1B3D
L1B35:  SHR
L1B36:  SHR
L1B37:  SHR
L1B38:  SHR
L1B39:  LPAI L1B3D
L1B3B:  JMP

L1B3C:  LDA  TMP07
L1B3D:  SHR
L1B3E:  SHR
L1B3F:  SHR
L1B40:  SHR
L1B41:  STAP                        ;>> 4: the middle digit
L1B42:  LDAI #$000
L1B43:  A4I  #$F
L1B44:  TST  TMP07
L1B45:  ANDP                        ;the digit, 0-$F  TMP07
L1B46:  STAP                        ;store to TMP07
L1B47:  LDA  TMP0E
L1B48:  SHR
L1B49:  LPAI L1B52
L1B4B:  JOS                         ;a digit has been printed: zeros print too  if the bit shifted out of A was 1 -> L1B52
L1B4C:  TST  TMP07
L1B4D:  LPAI L1B58
L1B4F:  JEQ                         ;a leading zero  if A = TMP07 -> L1B58
L1B50:  A4I  #$1
L1B51:  STA  TMP0E                  ;the first non-zero digit
L1B52:  LDA  TMP07
L1B53:  A8I  #$30                   ;+ '0'
L1B55:  LPAI L1B13
L1B57:  JMP

L1B58:  LDA  TMP02
L1B59:  S4I  #$1
L1B5A:  LPAI L1B52
L1B5C:  JEQ                         ;the last digit prints even when 0  if TMP02 = 1 -> L1B52
L1B5D:  LDAI #$000
L1B5E:  A8I  #$5B                   ;$5B: a space
L1B60:  LPAI L1B13
L1B62:  JMP

L1B63:  A4I  #$3
L1B64:  STA  TMP0F                  ;the low digit: TMP0F back to 3, and the next word for the digits after it
L1B65:  LDA  TMP05
L1B66:  A4I  #$1
L1B67:  STAP                        ;store to TMP05
L1B68:  LPAI L1B42
L1B6A:  JMP

PRINTRET:
L1B6B:  TST  RET0
L1B6C:  LPAP                        ;J = the address in RET0
L1B6D:  JMP                         ;J from RAM -> HUDSCORE, L1671, FORMATION, L1767, L17A2, HUDHISCORE, L182D, HUDCREDITS ...


;------------------------------------------------------------------------------
; PRINTCHR - Draw one character: CHRINDEX gives its stroke list in CHRSTROKES,
;   each stroke byte two nibbles naming points of the CHRGRID grid.
;------------------------------------------------------------------------------
PRINTCHR:
L1B6E:  LDAI #$C00
L1B6F:  A8I  #$29
L1B71:  ADD  TMP07
L1B72:  LKP                         ;CHRINDEX[code - $30]  table read $1C59-$1C7D
L1B74:  STAP                        ;store to TMP07
L1B75:  LDAI #$B00
L1B76:  A8I  #$EF
L1B78:  ADDP                        ;the stroke list: CHRSTROKES - 1 + index  TMP07
L1B79:  STAP                        ;store to TMP07
L1B7A:  LDA  TMP07
L1B7B:  A4I  #$1
L1B7C:  STAP                        ;store to TMP07
L1B7D:  LKP                         ;the next stroke byte  table read $1BF1-$1C58
L1B7F:  TST  TMP01
L1B80:  LPAI L1BC1
L1B82:  JEQ                         ;$FF: the character is done  if A = TMP01 -> L1BC1
L1B83:  STA  TMP0D
L1B84:  SHR
L1B85:  SHR
L1B86:  SHR
L1B87:  SHR
L1B88:  SHL
L1B89:  STA  TMP0C                  ;2 x the start point (high nibble)
L1B8A:  LDAI #$B00
L1B8B:  A8I  #$D2
L1B8D:  ADDP                        ;TMP0C
L1B8E:  STAP                        ;store to TMP0C
L1B8F:  A4I  #$1
L1B90:  LKP                         ;table read $1BD3-$1BEF
L1B92:  ADD  TMP04
L1B93:  STA  TMP09                  ;the start's y: + TMP04
L1B94:  LDA  TMP0C
L1B95:  LKP                         ;table read $1BD2-$1BEE
L1B97:  ADD  TMP03
L1B98:  STA  TMP08                  ;its x: + TMP03
L1B99:  SSA
L1B9A:  LDA  B,TMP09
L1B9B:  LPAI L1B9B
L1B9D:  JVN                         ;while the vector generator is busy -> L1B9B
L1B9E:  IV                          ;beam to the start
L1B9F:  LDAI #$000
L1BA0:  A4I  #$F
L1BA1:  TST  TMP0D
L1BA2:  ANDP                        ;TMP0D
L1BA3:  SHL
L1BA4:  STAP                        ;2 x the end point (low nibble)  store to TMP0D
L1BA5:  LDAI #$B00
L1BA6:  A8I  #$D2
L1BA8:  ADDP                        ;TMP0D
L1BA9:  STAP                        ;store to TMP0D
L1BAA:  A4I  #$1
L1BAB:  LKP                         ;table read $1BD3-$1BEF
L1BAD:  ADD  TMP04
L1BAE:  SUB  TMP09
L1BAF:  STA  TMP0B                  ;dy
L1BB0:  LDA  TMP0D
L1BB1:  LKP                         ;table read $1BD2-$1BEE
L1BB3:  ADD  TMP03
L1BB4:  SUB  TMP08
L1BB5:  STA  TMP0A                  ;dx
L1BB6:  LDA  TMP0A
L1BB7:  SSA
L1BB8:  LDA  B,TMP0B
L1BB9:  NV
L1BBA:  ADD  TMP08
L1BBB:  SSA
L1BBC:  ADD  B,TMP09
L1BBD:  DV                          ;the stroke
L1BBE:  LPAI L1B7A
L1BC0:  JMP

L1BC1:  LDAI #$000
L1BC2:  A4I  #$9
L1BC3:  ADD  TMP04
L1BC4:  STA  TMP09                  ;the next character: x + $18, y + 9 for the beam
L1BC5:  LDA  TMP06
L1BC6:  ADD  TMP03
L1BC7:  STAP                        ;store to TMP03
L1BC8:  A4I  #$3
L1BC9:  SSA
L1BCA:  LDA  B,TMP09
L1BCB:  LPAI L1BCB
L1BCD:  JVN                         ;while the vector generator is busy -> L1BCB
L1BCE:  IV                          ;beam there
L1BCF:  LPAI L1B09
L1BD1:  JMP

;$1BD2-$1D6F, read by LKP at L16A7, L16B5, L16BE, L16C7, L16D0, L16D9 ...
CHRGRID:
L1BD2:  .byte $00, $00              ;point 0      x  0  y  0
L1BD4:  .byte $04, $00              ;point 1      x  4  y  0
L1BD6:  .byte $08, $00              ;point 2      x  8  y  0
L1BD8:  .byte $0C, $00              ;point 3      x 12  y  0
L1BDA:  .byte $10, $00              ;point 4      x 16  y  0
L1BDC:  .byte $00, $0C              ;point 5      x  0  y 12
L1BDE:  .byte $04, $0C              ;point 6      x  4  y 12
L1BE0:  .byte $08, $0C              ;point 7      x  8  y 12
L1BE2:  .byte $0C, $0C              ;point 8      x 12  y 12
L1BE4:  .byte $10, $0C              ;point 9      x 16  y 12
L1BE6:  .byte $00, $18              ;point 10 (A) x  0  y 24
L1BE8:  .byte $04, $18              ;point 11 (B) x  4  y 24
L1BEA:  .byte $08, $18              ;point 12 (C) x  8  y 24
L1BEC:  .byte $0C, $18              ;point 13 (D) x 12  y 24
L1BEE:  .byte $10, $18              ;point 14 (E) x 16  y 24
CHRSTROKES:
L1BF0:  .byte $74                   ;'Q': 7-4, then the strokes of '0'
L1BF1:  .byte $AE                   ;'0', 'O': A-E, then the strokes of 'U'
L1BF2:  .byte $E4                   ;'U': E-4, then the strokes of 'L'
L1BF3:  .byte $40, $0A, $FF         ;'L': 4-0 0-A, end
L1BF6:  .byte $AE, $E9, $95, $50, $04, $FF  ;'2': A-E E-9 9-5 5-0 0-4, end
L1BFC:  .byte $04, $79, $4E, $EA, $FF  ;'3': 0-4 7-9 4-E E-A, end
L1C01:  .byte $04, $49, $95, $5A, $AE, $FF  ;'5', 'S': 0-4 4-9 9-5 5-A A-E, end
L1C07:  .byte $59, $94, $40, $0A, $FF  ;'6': 5-9 9-4 4-0 0-A, end
L1C0C:  .byte $2E, $EA, $FF         ;'7': 2-E E-A, end
L1C0F:  .byte $04                   ;'8': 0-4, then the strokes of 'A'
L1C10:  .byte $AE                   ;'A': A-E, then the strokes of 'H'
L1C11:  .byte $59, $E4, $A0, $FF    ;'H': 5-9 E-4 A-0, end
L1C15:  .byte $EA                   ;'9': E-A, then the strokes of '4'
L1C16:  .byte $A5, $59, $E4, $FF    ;'4': A-5 5-9 E-4, end
L1C1A:  .byte $69                   ;'B': 6-9, then the strokes of 'D'
L1C1B:  .byte $04, $4E, $EA, $B1, $FF  ;'D': 0-4 4-E E-A B-1, end
L1C20:  .byte $40                   ;'E': 4-0, then the strokes of 'F'
L1C21:  .byte $0A, $57, $AE, $FF    ;'F': 0-A 5-7 A-E, end
L1C25:  .byte $79, $94              ;'G': 7-9 9-4, then the strokes of 'C'
L1C27:  .byte $40, $0A, $AE, $FF    ;'C': 4-0 0-A A-E, end
L1C2B:  .byte $50, $03, $3D, $BE, $FF  ;'J': 5-0 0-3 3-D B-E, end
L1C30:  .byte $0A, $E5, $54, $FF    ;'K': 0-A E-5 5-4, end
L1C34:  .byte $0A, $A7, $7E, $E4, $FF  ;'M': 0-A A-7 7-E E-4, end
L1C39:  .byte $0A, $A4, $4E, $FF    ;'N': 0-A A-4 4-E, end
L1C3D:  .byte $48                   ;'R': 4-8, then the strokes of 'P'
L1C3E:  .byte $59, $9E, $EA, $A0, $FF  ;'P': 5-9 9-E E-A A-0, end
L1C43:  .byte $AE                   ;'T': A-E, then the strokes of '1'
L1C44:  .byte $C2, $FF              ;'1', 'I': C-2, end
L1C46:  .byte $A2, $2E, $FF         ;'V': A-2 2-E, end
L1C49:  .byte $A1, $17, $73, $3E, $FF  ;'W': A-1 1-7 7-3 3-E, end
L1C4E:  .byte $0E, $A4, $FF         ;'X': 0-E A-4, end
L1C51:  .byte $27, $7A, $7E, $FF    ;'Y': 2-7 7-A 7-E, end
L1C55:  .byte $AE, $E0, $04         ;'Z': A-E E-0 0-4, then the strokes of ' '
L1C58:  .byte $FF                   ;' ': , end
CHRINDEX:
L1C59:  .byte $01, $54, $06, $0C, $26, $11, $17, $1C, $1F, $25  ;index of '0'-'9'
L1C63:  .byte $20, $2A, $37, $2B, $30, $31, $35, $21, $54, $3B, $40, $03, $44  ;index of 'A'-'M'
L1C70:  .byte $49, $01, $4E, $00, $4D, $11, $53, $02, $56, $59, $5E, $61, $65  ;index of 'N'-'Z'
L1C7D:  .byte $68                   ;index of $5B (space)
FORMTAB:
L1C7E:  .byte $8E, $0C              ;pattern 0 at $1C8E
L1C80:  .byte $A2, $0C              ;pattern 1 at $1CA2
L1C82:  .byte $B6, $0C              ;pattern 2 at $1CB6
L1C84:  .byte $D4, $0C              ;pattern 3 at $1CD4
L1C86:  .byte $F2, $0C              ;pattern 4 at $1CF2
L1C88:  .byte $2E, $0D              ;pattern 5 at $1D2E
L1C8A:  .byte $06, $0D              ;pattern 6 at $1D06
L1C8C:  .byte $42, $0D              ;pattern 7 at $1D42
FORMDATA:
FORM0:
L1C8E:  .byte $00, $E0, $80, $E0, $20, $80, $20, $20, $80, $21  ;pattern 0 step 0: +0,-32,-128  -32,+32,-128  +32,+32,-128  (33 frames)
L1C98:  .byte $00, $0C, $00, $F4, $F4, $00, $0C, $F4, $00, $FF  ;pattern 0 step 1: +0,+12,+0  -12,-12,+0  +12,-12,+0  (last)
FORM1:
L1CA2:  .byte $E5, $E5, $A0, $E5, $1B, $A0, $17, $00, $A0, $25  ;pattern 1 step 0: -27,-27,-96  -27,+27,-96  +23,+0,-96  (37 frames)
L1CAC:  .byte $0E, $F2, $00, $0E, $0E, $00, $F5, $00, $00, $FF  ;pattern 1 step 1: +14,-14,+0  +14,+14,+0  -11,+0,+0  (last)
FORM2:
L1CB6:  .byte $00, $00, $C0, $00, $29, $C0, $00, $D7, $C0, $17  ;pattern 2 step 0: +0,+0,-64  +0,+41,-64  +0,-41,-64  (23 frames)
L1CC0:  .byte $00, $F5, $80, $00, $0B, $80, $00, $EA, $80, $16  ;pattern 2 step 1: +0,-11,-128  +0,+11,-128  +0,-22,-128  (22 frames)
L1CCA:  .byte $00, $00, $00, $08, $00, $00, $F8, $00, $00, $FF  ;pattern 2 step 2: +0,+0,+0  +8,+0,+0  -8,+0,+0  (last)
FORM3:
L1CD4:  .byte $00, $21, $A0, $00, $00, $A0, $00, $DF, $A0, $17  ;pattern 3 step 0: +0,+33,-96  +0,+0,-96  +0,-33,-96  (23 frames)
L1CDE:  .byte $F5, $00, $70, $0B, $00, $70, $00, $00, $70, $17  ;pattern 3 step 1: -11,+0,+112  +11,+0,+112  +0,+0,+112  (23 frames)
L1CE8:  .byte $F8, $F8, $00, $08, $F8, $00, $00, $08, $00, $FF  ;pattern 3 step 2: -8,-8,+0  +8,-8,+0  +0,+8,+0  (last)
FORM4:
L1CF2:  .byte $00, $18, $C0, $DB, $DB, $C0, $25, $DB, $C0, $11  ;pattern 4 step 0: +0,+24,-64  -37,-37,-64  +37,-37,-64  (17 frames)
L1CFC:  .byte $EC, $EC, $A0, $14, $EC, $A0, $00, $18, $A0, $11  ;pattern 4 step 1: -20,-20,-96  +20,-20,-96  +0,+24,-96  (17 frames)
FORM6:
L1D06:  .byte $14, $EC, $80, $00, $18, $80, $EC, $EC, $80, $11  ;pattern 6 step 0: +20,-20,-128  +0,+24,-128  -20,-20,-128  (17 frames)
L1D10:  .byte $00, $0C, $60, $F6, $F6, $60, $0A, $F6, $60, $11  ;pattern 6 step 1: +0,+12,+96  -10,-10,+96  +10,-10,+96  (17 frames)
L1D1A:  .byte $F8, $F8, $40, $08, $F8, $40, $00, $08, $40, $11  ;pattern 6 step 2: -8,-8,+64  +8,-8,+64  +0,+8,+64  (17 frames)
L1D24:  .byte $08, $F8, $00, $00, $08, $00, $F8, $F8, $00, $FF  ;pattern 6 step 3: +8,-8,+0  +0,+8,+0  -8,-8,+0  (last)
FORM5:
L1D2E:  .byte $00, $18, $C0, $D7, $D7, $C0, $29, $D7, $C0, $11  ;pattern 5 step 0: +0,+24,-64  -41,-41,-64  +41,-41,-64  (17 frames)
L1D38:  .byte $14, $EC, $A0, $00, $18, $A0, $EC, $EC, $A0, $11  ;pattern 5 step 1: +20,-20,-96  +0,+24,-96  -20,-20,-96  (17 frames)
FORM7:
L1D42:  .byte $EC, $EC, $80, $14, $EC, $80, $00, $18, $80, $11  ;pattern 7 step 0: -20,-20,-128  +20,-20,-128  +0,+24,-128  (17 frames)
L1D4C:  .byte $00, $0C, $60, $F6, $F6, $60, $0A, $F6, $60, $11  ;pattern 7 step 1: +0,+12,+96  -10,-10,+96  +10,-10,+96  (17 frames)
L1D56:  .byte $08, $F8, $40, $00, $0A, $40, $F8, $F8, $40, $11  ;pattern 7 step 2: +8,-8,+64  +0,+10,+64  -8,-8,+64  (17 frames)
L1D60:  .byte $F8, $F8, $00, $08, $F8, $00, $00, $08, $00, $FF  ;pattern 7 step 3: -8,-8,+0  +8,-8,+0  +0,+8,+0  (last)
L1D6A:  .byte $E2, $FF, $D2, $80, $0D, $2A

;------------------------------------------------------------------------------
; TESTSNDOFF - Test mode: every sound off, then on to the test pattern loop at
;   $1005.
;------------------------------------------------------------------------------
TESTSNDOFF:
L1D70:  LDAI #$000
L1D71:  A8I  #$1A
L1D73:  OUT  OUT_SND_DATA           ;sound: laser off
L1D74:  SHR
L1D75:  OUT  OUT_SND_A0
L1D76:  SHR
L1D77:  OUT  OUT_SND_A1
L1D78:  SHR
L1D79:  OUT  OUT_SND_A2
L1D7A:  SHR
L1D7B:  OUT  OUT_SND_STROBE
L1D7C:  SHR
L1D7D:  OUT  OUT_SND_STROBE
L1D7E:  LDAI #$000
L1D7F:  A8I  #$14
L1D81:  OUT  OUT_SND_DATA           ;sound: hyperspace off
L1D82:  SHR
L1D83:  OUT  OUT_SND_A0
L1D84:  SHR
L1D85:  OUT  OUT_SND_A1
L1D86:  SHR
L1D87:  OUT  OUT_SND_A2
L1D88:  SHR
L1D89:  OUT  OUT_SND_STROBE
L1D8A:  SHR
L1D8B:  OUT  OUT_SND_STROBE
L1D8C:  LDAI #$000
L1D8D:  A8I  #$1C
L1D8F:  OUT  OUT_SND_DATA           ;sound: rumble off
L1D90:  SHR
L1D91:  OUT  OUT_SND_A0
L1D92:  SHR
L1D93:  OUT  OUT_SND_A1
L1D94:  SHR
L1D95:  OUT  OUT_SND_A2
L1D96:  SHR
L1D97:  OUT  OUT_SND_STROBE
L1D98:  SHR
L1D99:  OUT  OUT_SND_STROBE
L1D9A:  LDAI #$000
L1D9B:  A8I  #$18
L1D9D:  OUT  OUT_SND_DATA           ;sound: shield off
L1D9E:  SHR
L1D9F:  OUT  OUT_SND_A0
L1DA0:  SHR
L1DA1:  OUT  OUT_SND_A1
L1DA2:  SHR
L1DA3:  OUT  OUT_SND_A2
L1DA4:  SHR
L1DA5:  OUT  OUT_SND_STROBE
L1DA6:  SHR
L1DA7:  OUT  OUT_SND_STROBE
L1DA8:  LPAI TESTLOOP
L1DAA:  JMP

L1DAB:  .byte $E2, $FF, $43, $5A, $4D, $45, $49, $41  ;$1DAB-$1DBF, read by LKP at L16A7, L16B5, L16BE, L16C7, L16D0, L16D9 ...
L1DB3:  .byte $42, $44, $48, $53, $50, $F6, $F4, $FC
L1DBB:  .byte $FA, $FE, $01, $07, $08

;------------------------------------------------------------------------------
; NEWWAVE - Start a wave: clear the three fighters, take the next pseudo-random
;   value (RANDOM_LO / RANDOM_HI), and from it the formation, the fighters'
;   starting positions and speeds and the points per hit (HIT_POINTS). Returns
;   to MOVEFTR through RET1.
;------------------------------------------------------------------------------
NEWWAVE:
L1DC0:  NOP
L1DC1:  LDAI #$000
L1DC2:  SETP $6
L1DC3:  TST  FTRS_LEFT
L1DC4:  LPAI L1DD5
L1DC6:  JEQ                         ;attract: no sound  if FTRS_LEFT = 0 -> L1DD5
L1DC7:  LDAI #$000
L1DC8:  A8I  #$11
L1DCA:  OUT  OUT_SND_DATA           ;sound: bit 7 on
L1DCB:  SHR
L1DCC:  OUT  OUT_SND_A0
L1DCD:  SHR
L1DCE:  OUT  OUT_SND_A1
L1DCF:  SHR
L1DD0:  OUT  OUT_SND_A2
L1DD1:  SHR
L1DD2:  OUT  OUT_SND_STROBE
L1DD3:  SHR
L1DD4:  OUT  OUT_SND_STROBE
L1DD5:  LDAI #$000
L1DD6:  SETP $2
L1DD7:  STA  HITS                   ;no hits yet this wave
L1DD8:  SETP $7
L1DD9:  STA  WAVE_TIMER             ;hyperspace over
L1DDA:  SETP $3
L1DDB:  STA  FTR1_STATE             ;each fighter: not exploding, not flying away
L1DDC:  STA  FTR1_DESTY
L1DDD:  STA  FTR1_AWAY
L1DDE:  SETP $4
L1DDF:  STA  FTR2_STATE
L1DE0:  STA  FTR2_DESTY
L1DE1:  STA  FTR2_AWAY
L1DE2:  SETP $5
L1DE3:  STA  FTR3_STATE
L1DE4:  STA  FTR3_DESTY
L1DE5:  STA  FTR3_AWAY
L1DE6:  LDAI #$F00
L1DE7:  SETP $3
L1DE8:  STA  FTR1_Z                 ;all start far away, z = $F00
L1DE9:  SETP $4
L1DEA:  STA  FTR2_Z
L1DEB:  SETP $5
L1DEC:  STA  FTR3_Z
L1DED:  SETP $2
L1DEE:  SSA
L1DEF:  LDA  B,RANDOM_HI            ;step the pseudo-random generator RANDOM_HI:RANDOM_LO (shifts and adds)
L1DF0:  LDAI #$000
L1DF1:  SHRB
L1DF2:  SHRB
L1DF3:  SHRB
L1DF4:  ADD  RANDOM_LO
L1DF5:  SSA
L1DF6:  LDAP B                      ;RANDOM_LO
L1DF7:  STAP                        ;store to RANDOM_LO
L1DF8:  LDAI #$200
L1DF9:  ANDP                        ;RANDOM_LO
L1DFA:  SHL
L1DFB:  STAP                        ;store to RANDOM_LO
L1DFC:  SSA
L1DFD:  ADDP B                      ;RANDOM_LO
L1DFE:  LDA  RANDOM_HI
L1DFF:  SHRB
L1E00:  STAP                        ;store to RANDOM_HI
L1E01:  SSA
L1E02:  STA  B,RANDOM_LO
L1E03:  LDAI #$000
L1E04:  A8I  #$FF
L1E06:  SETP $2
L1E07:  TST  RANDOM_HI
L1E08:  ANDP                        ;RANDOM_HI
L1E09:  A8I  #$FF
L1E0B:  SETP $5
L1E0C:  STA  FTR3_DESTX             ;destinations in x: fighter 3 at (RANDOM_HI & $FF) + $FF,
L1E0D:  LDAI #$000
L1E0E:  SETP $3
L1E0F:  STA  FTR1_DESTX             ;fighter 1 at 0,
L1E10:  SETP $5
L1E11:  SUB  FTR3_DESTX
L1E12:  SETP $4
L1E13:  STA  FTR2_DESTX             ;fighter 2 opposite fighter 3
L1E14:  LDAI #$C00
L1E15:  STA  FTR2_DESTZ
L1E16:  SETP $5
L1E17:  STA  FTR3_DESTZ
L1E18:  SETP $3
L1E19:  STA  FTR1_DESTZ             ;all three to z = $C00
L1E1A:  SETP $2
L1E1B:  LDA  RANDOM_LO
L1E1C:  SHR
L1E1D:  SHR
L1E1E:  SHR
L1E1F:  LPAI L1E9D
L1E21:  JOS                         ;bits 3 and 4 of RANDOM_LO pick one of three start layouts  if the bit shifted out of A was 1 -> L1E9D
L1E22:  SHR
L1E23:  JOS                         ;if the bit shifted out of A was 1 -> L1E9D
L1E24:  SETP $2
L1E25:  LDA  RANDOM_HI
L1E26:  ASR
L1E27:  LPAI L1E5B
L1E29:  JOS                         ;if the bit shifted out of A was 1 -> L1E5B
L1E2A:  SETP $3
L1E2B:  STA  FTR1_Y
L1E2C:  ASR
L1E2D:  ADDP                        ;FTR1_Y
L1E2E:  STAP                        ;store to FTR1_Y
L1E2F:  S8I  #$7F
L1E31:  SETP $4
L1E32:  STA  FTR2_Y
L1E33:  A8I  #$FE
L1E35:  SETP $5
L1E36:  STA  FTR3_Y
L1E37:  ASR
L1E38:  ASR
L1E39:  ASR
L1E3A:  ASR
L1E3B:  ASR
L1E3C:  ASR
L1E3D:  ASR
L1E3E:  STA  FTR3_HEADY
L1E3F:  LDAI #$000
L1E40:  SUBP                        ;FTR3_HEADY
L1E41:  STAP                        ;store to FTR3_HEADY
L1E42:  SETP $4
L1E43:  STA  FTR2_HEADY
L1E44:  SETP $3
L1E45:  STA  FTR1_HEADY
L1E46:  LDAI #$800
L1E47:  SETP $2
L1E48:  TST  RANDOM_HI
L1E49:  LPAI L1E88
L1E4B:  JLT                         ;if RANDOM_HI < $800 -> L1E88
L1E4C:  LDAI #$900
L1E4D:  SETP $3
L1E4E:  STA  FTR1_X
L1E4F:  A8I  #$FF
L1E51:  SETP $4
L1E52:  STA  FTR2_X
L1E53:  SETP $5
L1E54:  STA  FTR3_X
L1E55:  LDAI #$000
L1E56:  A8I  #$20
L1E58:  LPAI L1E94
L1E5A:  JMP

L1E5B:  SETP $3
L1E5C:  STA  FTR1_X
L1E5D:  S8I  #$7F
L1E5F:  SETP $4
L1E60:  STA  FTR2_X
L1E61:  A8I  #$FE
L1E63:  SETP $5
L1E64:  STA  FTR3_X
L1E65:  ASR
L1E66:  ASR
L1E67:  ASR
L1E68:  ASR
L1E69:  ASR
L1E6A:  ASR
L1E6B:  ASR
L1E6C:  STA  FTR3_HEADX
L1E6D:  LDAI #$000
L1E6E:  SUBP                        ;FTR3_HEADX
L1E6F:  STAP                        ;store to FTR3_HEADX
L1E70:  SETP $4
L1E71:  STA  FTR2_HEADX
L1E72:  SETP $3
L1E73:  STA  FTR1_HEADX
L1E74:  LDAI #$700
L1E75:  SETP $4
L1E76:  STA  FTR2_Y
L1E77:  SETP $5
L1E78:  STA  FTR3_Y
L1E79:  S8I  #$FF
L1E7B:  SETP $3
L1E7C:  STA  FTR1_Y
L1E7D:  LDAI #$F00
L1E7E:  A8I  #$E0
L1E80:  STA  FTR1_HEADY
L1E81:  SETP $5
L1E82:  STA  FTR3_HEADY
L1E83:  SETP $4
L1E84:  STA  FTR2_HEADY
L1E85:  LPAI L1E9A
L1E87:  JMP

L1E88:  LDAI #$700
L1E89:  SETP $3
L1E8A:  STA  FTR1_X
L1E8B:  S8I  #$FF
L1E8D:  SETP $4
L1E8E:  STA  FTR2_X
L1E8F:  SETP $5
L1E90:  STA  FTR3_X
L1E91:  LDAI #$F00
L1E92:  A8I  #$E0
L1E94:  SETP $3
L1E95:  STA  FTR1_HEADX
L1E96:  SETP $4
L1E97:  STA  FTR2_HEADX
L1E98:  SETP $5
L1E99:  STA  FTR3_HEADX
L1E9A:  LPAI L1EF8
L1E9C:  JMP

L1E9D:  SETP $2
L1E9E:  LDA  RANDOM_HI
L1E9F:  ASR
L1EA0:  SETP $4
L1EA1:  STA  FTR2_Y
L1EA2:  ASR
L1EA3:  ADDP                        ;FTR2_Y
L1EA4:  STAP                        ;store to FTR2_Y
L1EA5:  ASR
L1EA6:  ASR
L1EA7:  ASR
L1EA8:  ASR
L1EA9:  ASR
L1EAA:  ASR
L1EAB:  ASR
L1EAC:  STA  FTR2_HEADY
L1EAD:  LDAI #$000
L1EAE:  SUBP                        ;FTR2_HEADY
L1EAF:  STAP                        ;store to FTR2_HEADY
L1EB0:  LDAI #$900
L1EB1:  STA  FTR2_X
L1EB2:  LDAI #$000
L1EB3:  A8I  #$18
L1EB5:  STA  FTR2_HEADX
L1EB6:  LDAI #$700
L1EB7:  SETP $3
L1EB8:  STA  FTR1_Y
L1EB9:  SETP $5
L1EBA:  STA  FTR3_X
L1EBB:  LDAI #$F00
L1EBC:  A8I  #$E8
L1EBE:  STA  FTR3_HEADX
L1EBF:  SETP $3
L1EC0:  STA  FTR1_HEADY
L1EC1:  SETP $2
L1EC2:  LDA  RANDOM_LO
L1EC3:  SHL
L1EC4:  SHL
L1EC5:  ASR
L1EC6:  SETP $3
L1EC7:  STA  FTR1_X
L1EC8:  ASR
L1EC9:  ASR
L1ECA:  ASR
L1ECB:  ASR
L1ECC:  ASR
L1ECD:  ASR
L1ECE:  ASR
L1ECF:  STA  FTR1_HEADX
L1ED0:  SETP $2
L1ED1:  SSA
L1ED2:  LDA  B,RANDOM_HI
L1ED3:  LDAI #$000
L1ED4:  SHRB
L1ED5:  SHRB
L1ED6:  SHRB
L1ED7:  ADD  RANDOM_LO
L1ED8:  SSA
L1ED9:  LDAP B                      ;RANDOM_LO
L1EDA:  STAP                        ;store to RANDOM_LO
L1EDB:  LDAI #$200
L1EDC:  ANDP                        ;RANDOM_LO
L1EDD:  SHL
L1EDE:  STAP                        ;store to RANDOM_LO
L1EDF:  SSA
L1EE0:  ADDP B                      ;RANDOM_LO
L1EE1:  LDA  RANDOM_HI
L1EE2:  SHRB
L1EE3:  STAP                        ;store to RANDOM_HI
L1EE4:  SSA
L1EE5:  STA  B,RANDOM_LO
L1EE6:  LDA  RANDOM_HI
L1EE7:  ASR
L1EE8:  SETP $5
L1EE9:  STA  FTR3_Y
L1EEA:  ASR
L1EEB:  ADDP                        ;FTR3_Y
L1EEC:  STAP                        ;store to FTR3_Y
L1EED:  ASR
L1EEE:  ASR
L1EEF:  ASR
L1EF0:  ASR
L1EF1:  ASR
L1EF2:  ASR
L1EF3:  ASR
L1EF4:  STA  FTR3_HEADY
L1EF5:  LDAI #$000
L1EF6:  SUBP                        ;FTR3_HEADY
L1EF7:  STAP                        ;store to FTR3_HEADY
L1EF8:  LDAI #$000
L1EF9:  A8I  #$20
L1EFB:  SETP $2
L1EFC:  STA  TMP2E                  ;TMP2E: the wave's speed, $20 to start
L1EFD:  SETP $6
L1EFE:  TST  SCORE_HI
L1EFF:  LPAI L1F48
L1F01:  JLT                         ;below 200 points: $20  if SCORE_HI < $20 -> L1F48
L1F02:  LDAI #$200
L1F03:  TST  SCORE_HI
L1F04:  LPAI L1F3E
L1F06:  JLT                         ;below 2000: $20 + SCORE_HI / 32  if SCORE_HI < $200 -> L1F3E
L1F07:  SHL
L1F08:  TST  SCORE_HI
L1F09:  LPAI L1F30
L1F0B:  JLT                         ;below 4000: $30 + (SCORE_HI - $200) / 64  if SCORE_HI < A -> L1F30
L1F0C:  LDAI #$600
L1F0D:  TST  SCORE_HI
L1F0E:  LPAI L1F21
L1F10:  JLT                         ;below 6000: $38 + (SCORE_HI - $400) / 128  if SCORE_HI < $600 -> L1F21
L1F11:  LDAI #$000
L1F12:  A8I  #$3C
L1F14:  SETP $2
L1F15:  STA  TMP2E                  ;else $3C + (SCORE_HI - $600) / 256
L1F16:  SETP $6
L1F17:  LDA  SCORE_HI
L1F18:  SHR
L1F19:  SHR
L1F1A:  SHR
L1F1B:  SHR
L1F1C:  S8I  #$60
L1F1E:  LPAI L1F41
L1F20:  JMP

L1F21:  LDAI #$000
L1F22:  A8I  #$38
L1F24:  SETP $2
L1F25:  STA  TMP2E
L1F26:  SETP $6
L1F27:  LDA  SCORE_HI
L1F28:  SHR
L1F29:  SHR
L1F2A:  SHR
L1F2B:  S8I  #$80
L1F2D:  LPAI L1F41
L1F2F:  JMP

L1F30:  LDAI #$000
L1F31:  A8I  #$30
L1F33:  SETP $2
L1F34:  STA  TMP2E
L1F35:  SETP $6
L1F36:  LDA  SCORE_HI
L1F37:  SHR
L1F38:  SHR
L1F39:  S8I  #$80
L1F3B:  LPAI L1F41
L1F3D:  JMP

L1F3E:  SETP $6
L1F3F:  LDA  SCORE_HI
L1F40:  SHR
L1F41:  SHR
L1F42:  SHR
L1F43:  SHR
L1F44:  SHR
L1F45:  SETP $2
L1F46:  ADD  TMP2E
L1F47:  STAP                        ;store to TMP2E
L1F48:  SETP $2
L1F49:  LDA  RANDOM_HI
L1F4A:  SHR
L1F4B:  LPAI L1F6C
L1F4D:  JOS                         ;RANDOM_HI bits 0 and 1 pick the model and the points:  if the bit shifted out of A was 1 -> L1F6C
L1F4E:  SHR
L1F4F:  LPAI L1F5F
L1F51:  JOS                         ;if the bit shifted out of A was 1 -> L1F5F
L1F52:  LDAI #$000
L1F53:  A8I  #$23
L1F55:  STA  HIT_POINTS             ;00: 23 points, model 4 ($539), speed + $C
L1F56:  LDA  TMP2E
L1F57:  A4I  #$C
L1F58:  STAP                        ;store to TMP2E
L1F59:  LDAI #$500
L1F5A:  A8I  #$39
L1F5C:  LPAI L1F83
L1F5E:  JMP

L1F5F:  LDAI #$000
L1F60:  A8I  #$17
L1F62:  STA  HIT_POINTS             ;10: 17 points, model 3 ($503), speed + 8
L1F63:  LDA  TMP2E
L1F64:  A4I  #$8
L1F65:  STAP                        ;store to TMP2E
L1F66:  LDAI #$500
L1F67:  A8I  #$03
L1F69:  LPAI L1F83
L1F6B:  JMP

L1F6C:  SHR
L1F6D:  LPAI L1F7D
L1F6F:  JOS                         ;if the bit shifted out of A was 1 -> L1F7D
L1F70:  LDAI #$000
L1F71:  A8I  #$11
L1F73:  STA  HIT_POINTS             ;01: 11 points, model 2 ($4C7), speed + 4
L1F74:  LDA  TMP2E
L1F75:  A4I  #$4
L1F76:  STAP                        ;store to TMP2E
L1F77:  LDAI #$400
L1F78:  A8I  #$C7
L1F7A:  LPAI L1F83
L1F7C:  JMP

L1F7D:  LDAI #$000
L1F7E:  A4I  #$7
L1F7F:  STA  HIT_POINTS             ;11: 7 points, model 1 ($481)
L1F80:  LDAI #$400
L1F81:  A8I  #$81
L1F83:  SETP $3
L1F84:  STA  FTR1_MODEL
L1F85:  SETP $4
L1F86:  STA  FTR2_MODEL
L1F87:  SETP $5
L1F88:  STA  FTR3_MODEL             ;all three fighters the same model
L1F89:  LDAI #$000
L1F8A:  SETP $6
L1F8B:  TST  FTRS_LEFT
L1F8C:  LPAI L1F99
L1F8E:  JEQ                         ;if FTRS_LEFT = 0 -> L1F99
L1F8F:  A8I  #$10
L1F91:  SETP $6
L1F92:  TST  SCORE_HI
L1F93:  JCZ                         ;100 points or more: the speed stands  if $10 < SCORE_HI -> L1F99
L1F94:  LDAP                        ;SCORE_HI
L1F95:  SHL
L1F96:  A4I  #$F
L1F97:  SETP $2
L1F98:  STA  TMP2E                  ;below 100: SCORE_HI x 2 + $F, slower
L1F99:  SETP $2
L1F9A:  LDA  TMP2E
L1F9B:  SETP $3
L1F9C:  STA  FTR1_SPEED
L1F9D:  SETP $4
L1F9E:  STA  FTR2_SPEED
L1F9F:  SETP $5
L1FA0:  STA  FTR3_SPEED             ;all three the same speed
L1FA1:  LDAI #$C00
L1FA2:  A8I  #$7E
L1FA4:  SETP $2
L1FA5:  STA  TMP2E
L1FA6:  LDAI #$000
L1FA7:  A4I  #$7
L1FA8:  SETP $2
L1FA9:  TST  RANDOM_LO
L1FAA:  ANDP                        ;RANDOM_LO
L1FAB:  SHL
L1FAC:  SETP $2
L1FAD:  ADD  TMP2E
L1FAE:  STAP                        ;FORMTAB + 2 x (RANDOM_LO & 7): the formation pattern  store to TMP2E
L1FAF:  A4I  #$1
L1FB0:  LKP                         ;table read $1C7F-$1C8D
L1FB2:  STA  FORM_PTR
L1FB3:  SSA
L1FB4:  LDAP B                      ;FORM_PTR
L1FB5:  LDA  TMP2E
L1FB6:  LKP                         ;table read $1C7E-$1C8C
L1FB8:  STAP                        ;store to TMP2E
L1FB9:  LDAI #$000
L1FBA:  SHRB
L1FBB:  SHRB
L1FBC:  SHRB
L1FBD:  SHRB
L1FBE:  ADDP                        ;TMP2E
L1FBF:  STA  FORM_PTR               ;FORM_PTR = the pattern's first step
L1FC0:  LDAI #$000
L1FC1:  A4I  #$7
L1FC2:  STA  FORM_TIMER             ;its first step in 7 frames
L1FC3:  SETP $1
L1FC4:  TST  RET1
L1FC5:  LPAP                        ;J = the address in RET1
L1FC6:  SETP $1
L1FC7:  T4K                         ;J from RAM -> MOVEFTR

DEVJUNK2:
L1FC8:  .byte $E2, $FF, $10, $40, $08, $08, $41, $02  ;$1FC8-$1FFF, read by LKP at L16A7, L16B5, L16BE, L16C7, L16D0, L16D9 ...
L1FD0:  .byte $00, $82, $42, $48, $09, $09, $20, $42
L1FD8:  .byte $21, $01, $20, $08, $22, $12, $11, $10
L1FE0:  .byte $10, $88, $42, $48, $49, $24, $24, $92
L1FE8:  .byte $42, $49, $24, $42, $49, $20, $84, $24
L1FF0:  .byte $84, $10, $92, $09, $10, $92, $48, $49
L1FF8:  .byte $09, $20, $82, $44, $04, $24, $90, $90

;End of ROM. The CCPU has no vectors: it starts at $0000 on reset and on a
;watchdog timeout.

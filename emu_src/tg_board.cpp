// Tail Gunner board: the inputs, DIP switches, coin latch and joystick comparator
// around the CCPU. Taken from the AAE Cinematronics driver
// (AAE's drivers\cinematronics_driver.cpp, coin handlers / get_ccpu_inputs /
// get_ccpu_switches / coin_handler / joystick_read) with the input-port reads
// replaced by the board state below.
#include "tg_emu.h"

// ---------------------------------------------------------------- state
static UINT8  sw_port = 0xff;      // SWITCHES: DIPs, bit 7 = COIN1 (active low, 1 = no coin)
static UINT8  dip_bits = 0x7f;     // the DIP part of sw_port (bits 0-6)
static UINT16 in_port = 0xffff;    // INPUTS, active low: bit 5 fire, 6 shield, 7 start
static int    stick_x = 0x80, stick_y = 0x80;

// Coin handling.
static UINT8 coin_detected;
static UINT8 coin_last_reset;
static UINT8 coin_last_input = 1;

// ---------------------------------------------------------------- coin
static void input_changed(int coin_inserted)
{
	/* on the falling edge of a new coin, set the coin_detected flag */
	if (coin_inserted == 0 && coin_last_input != 0)
		coin_detected = 1;
	coin_last_input = (UINT8)coin_inserted;
}

/* Samples the active-low COIN1 bit (SWITCHES bit 7) for a new coin edge.
   Called on every switch read and once per frame, so a coin pulse is
   latched even if the game does not poll while it is held. */
void coin_sample(void)
{
	input_changed((sw_port & 0x80) ? 1 : 0);
}

static int coin_read(void)
{
	return !coin_detected;
}

// ---------------------------------------------------------------- host side
void tg_board_init(void)
{
	in_port = 0xffff;
	stick_x = stick_y = 0x80;
	sw_port = (UINT8)(dip_bits | 0x80);
	coin_detected = 0;
	coin_last_reset = 0;
	coin_last_input = 1;
}

void tg_board_set_dips(UINT8 dip_byte)
{
	dip_bits = dip_byte & 0x7f;
	sw_port = (UINT8)((sw_port & 0x80) | dip_bits);
}

void tg_board_set_buttons(int fire, int shield, int start)
{
	in_port = 0xffff;
	if (fire)   in_port &= (UINT16)~0x20;
	if (shield) in_port &= (UINT16)~0x40;
	if (start)  in_port &= (UINT16)~0x80;
}

void tg_board_set_coin(int pressed)
{
	sw_port = (UINT8)(dip_bits | (pressed ? 0x00 : 0x80));
}

void tg_board_set_stick(int x, int y)
{
	stick_x = x < 0x20 ? 0x20 : x > 0xe0 ? 0xe0 : x;
	stick_y = y < 0x20 ? 0x20 : y > 0xe0 ? 0xe0 : y;
}

// ---------------------------------------------------------------- CCPU callbacks
UINT16 get_ccpu_inputs(int offset)
{
	return (UINT16)((in_port >> offset) & 1);
}

UINT16 get_ccpu_switches(int offset)
{
	static const UINT8 switch_shuffle[8] = { 2,5,4,3,0,1,6,7 };
	/* Bit 7 is the coin latch (MAME coin_input_r): set on a coin's falling
	   edge, held until the game pulses coin reset on output 5. */
	if (offset == 7)
	{
		coin_sample();
		return (UINT16)(coin_read() & 1);
	}

	return (UINT16)((sw_port >> switch_shuffle[offset]) & 1);
}

void coin_handler(int data)//coin_reset_w
{
	/* on the rising edge of a coin reset, clear the coin_detected flag */
	if (coin_last_reset != data && data != 0)
	{
		coin_detected = 0;
	}
	coin_last_reset = (UINT8)data;
}

UINT8 joystick_read(void)
{
	int xval = (INT16)(cpunum_get_reg(0, CCPU_X) << 4) >> 4;
	UINT32 analog = (UINT32)(MUX_VAL ? stick_x : stick_y);

	return (UINT8)(((analog << 4) - (UINT32)xval) < 0x800);
}

// Tail Gunner sound: the sound-latch decoding copied verbatim from AAE's
// AAE's sndhrdwr\cinematronics_sound.cpp (cini_sound_control_w, the Tail Gunner part of
// init_cinemat_snd, tailg_sound). That file cannot be compiled whole (Z80,
// AY8910 and Demon dependencies), so only the Tail Gunner pieces live here.
//
// AAE sample numbers (tailg_samples order) are mapped to mixer sample ids
// through a table, so a missing wav does not shift the others.
#include "tg_emu.h"
#include "mixer.h"
#include "log.h"
#include <string.h>

// ---------------------------------------------------------------- sample glue
static const char* const sample_names[TG_NUM_SAMPLES] = {
	"hypersp.wav", "sexplode.wav", "slaser.wav", "shield.wav", "bounce.wav", "thrust1.wav"
};
static int      sample_id[TG_NUM_SAMPLES];
static unsigned start_count[TG_NUM_SAMPLES];
static int      mixer_active;

void tg_sound_set_active(int mixer_running) { mixer_active = mixer_running; }

static void tg_sample_start(int chan, int samplenum, int loop)
{
	if (samplenum < 0 || samplenum >= TG_NUM_SAMPLES) return;
	start_count[samplenum]++;
	if (mixer_active && sample_id[samplenum] >= 0)
		sample_start(chan, sample_id[samplenum], loop);
}
static void tg_sample_stop(int chan) { if (mixer_active) sample_stop(chan); }
static void tg_sample_end(int chan)  { if (mixer_active) sample_end(chan); }

// The copied code below calls the AAE names.
#define sample_start(c, s, l) tg_sample_start(c, s, l)
#define sample_stop(c)        tg_sample_stop(c)
#define sample_end(c)         tg_sample_end(c)

void tg_sound_load(const char* zip_path)
{
	for (int i = 0; i < TG_NUM_SAMPLES; i++)
	{
		sample_id[i] = -1;
		if (mixer_active && zip_path && zip_path[0])
		{
			sample_id[i] = load_sample(zip_path, sample_names[i]);
			if (sample_id[i] < 0)
				LOG_WARN("sound: sample %d (%s) missing in %s; that effect is silent", i, sample_names[i], zip_path);
		}
	}
}

unsigned tg_sound_start_count(int sample)
{
	return (sample >= 0 && sample < TG_NUM_SAMPLES) ? start_count[sample] : 0;
}

void tg_sound_log_stats(void)
{
	LOG_INFO("sound: sample_start calls  hypersp %u  sexplode %u  slaser %u  shield %u  bounce %u  thrust1 %u",
		start_count[0], start_count[1], start_count[2], start_count[3], start_count[4], start_count[5]);
}

void tg_sound_shutdown(void)
{
	for (int i = 0; i < TG_NUM_SAMPLES; i++)
		if (mixer_active && sample_id[i] >= 0) { ::sample_remove(sample_id[i]); sample_id[i] = -1; }
}

// ---------------------------------------------------------------- copied code
// Tail Gunner OUT register and sound mux register (current and previous).
static UINT8 OldOutReg = 0;
static UINT8 XRreg = 0;
static UINT8 OldXRreg = 0x22;

static UINT8 sound_control;
static void (*sound_write) (UINT8, UINT8) = nullptr;

void tailg_sound(UINT8 sound_val, UINT8 bits_changed);

// init_cinemat_snd(tailg_sound), Tail Gunner parts only
void tg_sound_reset(void)
{
	sound_control = 0x9f;

	/* Tail Gunner mux: same values as a first boot, so the first sound
	   after a restart is not swallowed by the previous game's state */
	OldOutReg = 0;
	XRreg = 0;
	OldXRreg = 0x22;

	sound_write = tailg_sound;
}

void cini_sound_control_w(int offset, int data)
{
	UINT8 oldval = sound_control;

	/* form an 8-bit value with the new bit */
	sound_control = (UINT8)((sound_control & ~(1 << offset)) | ((data & 1) << offset));

	/* if something changed, call the sound subroutine */
	if ((sound_control != oldval) && sound_write)
		(*sound_write)(sound_control, (UINT8)(sound_control ^ oldval));
}

void qb3_sound_w(int) {}   // Quantum-board sound, unused by Tail Gunner

void tailg_sound(UINT8 sound_val, UINT8 bits_changed)
{
	(void)bits_changed;
	UINT8   outReg;
	UINT8   outDiff;		/* changed bits */
	UINT8	outLow;			/* changed bits that have just gone low */
	UINT8	xrDiff;			/* changed bits */
	UINT8   xrHigh;			/* changed bits that have just gone high */
	UINT8	xrLow;			/* changed bits that have just gone low */
	UINT8	mask;

	/* outReg = New value of the CCPU's OUT register. */
	outReg = sound_val;

	outDiff = outReg ^ OldOutReg;		/* get bits that have changed state */
	outLow = outDiff & ~outReg;			/* get bits that have just gone low */

	if (outLow & 0x10)
	{
		mask = (UINT8)(0x01 << (outReg & 0x07));	/* get address of bit as a mask */

		if (outReg & 0x08)
			XRreg |= mask;		/* If DATA set, set bit */
		else
			XRreg &= ~mask;		/* else reset bit */

		/* check for new MUX sounds */

		xrDiff = XRreg ^ OldXRreg;	/* get diff's */
		xrLow = xrDiff & ~XRreg;	/* get bits that just went low */
		xrHigh = xrDiff & XRreg;	/* get bits that just went high */

		/*
		HYPERSPACE	0x20
		BOUNCE	    0x10
		SHIELD		0x08
		LASER		0x04
		RUMBLE	    0x02
		EXPLOSION   0x01
		*/

		if (xrLow & 0x20)
			sample_start(0, 0, 0);

		if (xrLow & 0x10)
			sample_start(4, 4, 0);

		if (xrLow & 0x08)
			sample_start(3, 3, 1);

		if (xrHigh & 0x08)
			sample_stop(3);

		/* laser - 0=on: loops while held (MAME start(2, 2, true)); the
		   release below lets the current pass finish instead of cutting */
		if (xrLow & 0x04)
			sample_start(2, 2, 1);

		if (xrHigh & 0x04)
			sample_end(2);

		if (xrLow & 0x02)
			sample_start(5, 5, 1);

		if (xrHigh & 0x02)
			sample_stop(5);

		if (xrLow & 0x01)
			sample_start(1, 1, 0);

		OldXRreg = XRreg;
	}

	OldOutReg = outReg;	/* save new OUT register */
}

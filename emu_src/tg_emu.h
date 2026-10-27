// Tail Gunner test emulator: the seams between tg_main.cpp (host), tg_board.cpp
// (inputs / coin / DIPs / joystick comparator) and tg_sound.cpp (sample sound).
#pragma once
#include "aae_mame_driver.h"
#include "ccpu.h"
#include "cinematronics_video.h"

// ---- board ---------------------------------------------------------------
void tg_board_init(void);                       // power-on state of the inputs and coin latch
void tg_board_set_dips(UINT8 dip_byte);         // SWITCHES port, bit 7 (coin) is managed separately
void tg_board_set_buttons(int fire, int shield, int start);
void tg_board_set_coin(int pressed);            // 1 = coin switch closed (drives the active-low bit 7)
void tg_board_set_stick(int x, int y);          // 0x20..0xE0, centre 0x80
void coin_sample(void);                         // once per frame, as AAE's run_cinemat does

// ---- sound ---------------------------------------------------------------
#define TG_NUM_SAMPLES 6
void tg_sound_load(const char* zip_path);       // loads the six samples (missing ones are skipped)
void tg_sound_reset(void);                      // init_cinemat_snd(tailg_sound) equivalent
void tg_sound_shutdown(void);
void tg_sound_set_active(int mixer_running);    // 0 = count calls only, never touch the mixer
unsigned tg_sound_start_count(int sample);      // sample_start calls since startup
void tg_sound_log_stats(void);

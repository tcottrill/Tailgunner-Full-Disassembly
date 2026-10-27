// Minimal stand-ins for the AAE framework pieces ccpu.cpp and
// cinematronics_video.cpp touch, so both compile UNMODIFIED from emu_src\cpu\
// into the Tail Gunner test emulator. Found first on the include path
// (/Iaae /Iplatform) because the cpu\ folder has no deftypes.h / aae_mame_driver.h.
#pragma once
#include <stdio.h>
#include "deftypes.h"
#include "log.h"        // LOG_INFO
#include "colordefs.h"  // MAKE_RGB

#define CPU0 0

struct AaeCpuInfo { int cpu_freq; };
struct AaeGameDrv { int fps; AaeCpuInfo cpu[1]; };
struct AaeRect { int min_x, max_x, min_y, max_y; };
struct AaeDrv { AaeRect visible_area; };

struct AaeMachine
{
	UINT8*      memory_region[1];   // the CCPU program image, read as READOP(addr)
	AaeGameDrv* gamedrv;
	AaeDrv*     drv;
};
extern AaeMachine* Machine;

// Vector list hooks (implemented by the host, tg_main.cpp)
inline void cache_clear() {}
void vector_clear_list();
void vector_add_point(int x, int y, unsigned int color, int intensity);

inline int cpu_scale_by_cycles(int v, int) { return v; }

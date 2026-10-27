// Minimal stand-ins for the AAE framework pieces ccpu.cpp touches, so the
// core compiles unmodified inside the tracing harness (tgtrace.cpp).
#pragma once
#include <stdio.h>
#include "deftypes.h"

#define CPU0 0

// The program ROM is read through this proxy so the harness sees every
// fetch: opcode, operand, LKP lookup and the FRM duplicate peek.
struct RomProxy
{
	UINT8 operator[](int addr) const;
};

struct AaeCpuInfo { int cpu_freq; };
struct AaeGameDrv { int fps; AaeCpuInfo cpu[1]; };
struct AaeMachine
{
	RomProxy memory_region[1];
	AaeGameDrv* gamedrv;
};
extern AaeMachine* Machine;

#define LOG_INFO(...) ((void)0)
inline void cache_clear() {}
inline void vector_clear_list() {}
inline int cpu_scale_by_cycles(int v, int) { return v; }

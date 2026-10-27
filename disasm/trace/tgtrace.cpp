// tgtrace -- run the Tailgunner ROM on the CCPU core and record what the
// program does: which bytes execute as opcodes, the P register and the
// accumulator in use at each one, every jump actually taken, every LKP table
// read, every RAM read and write, every OUT, and the vectors of each frame.
//
// The CPU is ccpu.cpp from the AAE emulator (emu_src/cpu), compiled here unmodified (it is
// #included so the harness can single-step it and read its registers). The
// board around it -- inputs, coin latch, joystick comparator -- follows the
// AAE Cinematronics driver (cinematronics_driver.cpp).
//
// usage: tgtrace <rom8k.bin> <script.txt> <out.json> [svgdir]
//
// Script commands (one per line, '#' starts a comment):
//   frames N          run N frames with the current inputs
//   coin              insert a coin (held low for 4 frames)
//   start N           hold START for N frames
//   fire on|off       hold or release button 1
//   shield on|off     hold or release button 2
//   stick X Y         analog stick, 0x20-0xE0 (0x80 = centre), decimal or 0x hex
//   switches V        DIP byte as the driver's SWITCHES port (bit 7 = coin, keep set)
//   random N SEED     N frames of random stick / fire / shield
//   snap NAME         write the next frame's vectors as svgdir/NAME.svg
//   ram NAME          print the 256 RAM words to stdout (for diffing)
//   autoaim P         cheat: in P% of hit tests the crosshair is put on the fighter

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <string>
#include <vector>
#include <set>
#include <map>

#include "../../emu_src/cpu/ccpu.cpp"

// ---------------------------------------------------------------- machine
static UINT8 rom[0x2000];
static AaeGameDrv gamedrv = { 38, { { 4980750 } } };
static AaeMachine machine;
AaeMachine* Machine = &machine;

static const int CYCLES_PER_FRAME = 4980750 / 38;

// ------------------------------------------------------------ trace state
struct Fetch { int addr; bool stream; };
static Fetch fetches[8];
static int nfetch;
static bool anomaly_pc;

UINT8 RomProxy::operator[](int addr) const
{
	if (nfetch < 8)
	{
		fetches[nfetch].addr = addr;
		fetches[nfetch].stream = (addr == (int)ccpu.PC - 1);
		nfetch++;
	}
	if (addr < 0 || addr >= 0x2000) anomaly_pc = true;
	return rom[addr & 0x1fff];
}

static unsigned exec_count[0x2000];
static unsigned short pmask[0x2000];
static unsigned char accmask[0x2000];
static bool operand[0x2000];
static bool skipped[0x2000];            // LKP pad byte / duplicate FRM
static std::map<int, std::set<int>> jumps;      // pc -> destinations taken
static std::map<int, std::set<int>> falls;      // pc -> fall-through seen (cond. jumps)
static std::map<int, std::set<int>> lkp;        // pc -> ROM addresses read
static std::map<int, std::set<int>> ram_r, ram_w; // RAM addr -> pcs
static std::map<int, std::set<int>> outs, inps; // pc -> port
static std::map<int, std::set<int>> jvals;      // pc of indirect jump -> J values
static std::set<int> anomalies;
static long frame_no;

// ---------------------------------------------------------------- board
static UINT8 sw_port = 0xff;     // SWITCHES (bit 7 = coin, active low)
static UINT16 in_port = 0xffff;  // INPUTS (bit 5 fire, 6 shield, 7 start)
static int stick_x = 0x80, stick_y = 0x80;
static UINT8 coin_detected, coin_last_reset, coin_last_input = 1;
static unsigned long long out_writes;

static void coin_sample()
{
	int coin_inserted = (sw_port & 0x80) ? 1 : 0;
	if (coin_inserted == 0 && coin_last_input != 0) coin_detected = 1;
	coin_last_input = coin_inserted;
}

UINT16 get_ccpu_inputs(int offset) { return (in_port >> offset) & 1; }

UINT16 get_ccpu_switches(int offset)
{
	static const UINT8 switch_shuffle[8] = { 2,5,4,3,0,1,6,7 };
	if (offset == 7) { coin_sample(); return !coin_detected; }
	return (sw_port >> switch_shuffle[offset]) & 1;
}

void coin_handler(int data)
{
	if (coin_last_reset != data && data != 0) coin_detected = 0;
	coin_last_reset = data;
}

UINT8 joystick_read(void)
{
	int xval = (INT16)(cpunum_get_reg(0, CCPU_X) << 4) >> 4;
	int analog = MUX_VAL ? stick_x : stick_y;
	return ((analog << 4) - xval) < 0x800;
}

struct Vec { short sx, sy, ex, ey; unsigned char shift, bright; };
static std::vector<Vec> frame_vecs;
static int vec_bright = 1;

void cinemat_vector_callback(INT16 sx, INT16 sy, INT16 ex, INT16 ey, UINT8 shift)
{
	frame_vecs.push_back({ sx, sy, ex, ey, shift, (unsigned char)vec_bright });
}
void vec_control_write(int data) { vec_bright = (data & 1) ? 0 : 1; }
void cini_sound_control_w(int, int) { out_writes++; }
void qb3_sound_w(int) {}

// RAM value statistics: every value each word was written with (up to 4096,
// all a 12-bit word can hold), and how many writes changed it
struct RamStat { unsigned writes = 0, changes = 0; std::set<int> values; };
static RamStat ram_stat[256];
static UINT16 ram_last[256];

static void note_write(int addr)
{
	addr &= 0xff;
	RamStat& s = ram_stat[addr];
	UINT16 v = CCPURAM[addr];
	if (s.writes && v != ram_last[addr]) s.changes++;
	s.writes++;
	s.values.insert(v);
	ram_last[addr] = v;
}

// autoaim: before the hit test reads the crosshair (FTRUPDATE, $0E84), move
// the crosshair onto the fighter being tested, in aim_pct percent of tests.
// A cheat, for reaching the scoring code and the later waves.
static int aim_pct;
static unsigned aim_rng = 12345;

// ---------------------------------------------------------------- stepping
static void step()
{
	int pc = ccpu.PC;
	if (aim_pct && pc == 0x0e84)
	{
		aim_rng = aim_rng * 1103515245u + 12345u;
		if ((int)((aim_rng >> 16) % 100) < aim_pct)
		{
			CCPURAM[0x2c] = CCPURAM[0x07];
			CCPURAM[0x2d] = CCPURAM[0x08];
		}
	}
	int p = ccpu.P;
	bool accb = (ccpu.acc == &ccpu.B);
	int i_before = ccpu.I;
	int j_before = ccpu.J;
	UINT8 op = rom[pc & 0x1fff];

	nfetch = 0;
	anomaly_pc = false;
	ccpu_execute(0);   // a budget of 0 runs exactly one instruction

	if (pc >= 0x2000 || anomaly_pc) { anomalies.insert(pc); }
	pc &= 0x1fff;
	exec_count[pc]++;
	pmask[pc] |= 1 << p;
	accmask[pc] |= accb ? 2 : 1;
	int len = (op == 0x20 || op == 0x30 || (op >> 4) == 4 || op == 0xe2 || op == 0xf2) ? 2 : 1;
	for (int k = 1; k < len; k++)
		if (op == 0xe2 || op == 0xf2) skipped[(pc + k) & 0x1fff] = true;
		else operand[(pc + k) & 0x1fff] = true;

	int hi = op >> 4, lo = op & 15;
	if (hi == 5 && lo != 7 && lo != 15)
	{
		int next = (pc + 1) & 0x1fff;
		if ((int)ccpu.PC != next) jumps[pc].insert(ccpu.PC);
		else falls[pc].insert(next);
		jvals[pc].insert(j_before);
	}
	if (op == 0xe2 || op == 0xf2)
		for (int k = 0; k < nfetch; k++)
			if (!fetches[k].stream) lkp[pc].insert(fetches[k].addr);
	if (op == 0xe5 || op == 0xf5)
		if ((int)ccpu.PC == pc + 2) skipped[(pc + 1) & 0x1fff] = true;

	int direct = (p << 4) | lo;
	switch (hi)
	{
	case 0x6: case 0x7: case 0xa: case 0xb: case 0xc: ram_r[direct].insert(pc); break;
	case 0xd: ram_w[direct].insert(pc); note_write(direct); break;
	case 0x1: inps[pc].insert(lo | (accb ? 0x10 : 0)); break;
	case 0x9: outs[pc].insert(lo | (accb ? 0x10 : 0)); break;
	case 0xe: case 0xf:
		switch (op)
		{
		case 0xe1: case 0xf1: case 0xe3: case 0xf3: case 0xe7: case 0xf7:
		case 0xe8: case 0xf8: case 0xe9: case 0xf9: case 0xea: case 0xfa:
			ram_r[i_before].insert(pc); break;
		case 0xe6: case 0xf6: ram_w[i_before].insert(pc); note_write(i_before); break;
		}
		break;
	}
}

static std::string snap_name;
static std::string svgdir;

static void write_svg(const std::string& name)
{
	std::string path = svgdir + "/" + name + ".svg";
	FILE* f = fopen(path.c_str(), "w");
	if (!f) return;
	fprintf(f, "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 1024 800' "
		"style='background:#000'><g stroke-linecap='round'>\n");
	for (auto& v : frame_vecs)
	{
		// screen Y grows downward; the game's Y grows upward
		bool dot = v.sx == v.ex && v.sy == v.ey;
		fprintf(f, "<line x1='%d' y1='%d' x2='%d' y2='%d' stroke='%s' stroke-width='%s'/>\n",
			v.sx, 800 - v.sy, v.ex + (dot ? 1 : 0), 800 - v.ey,
			v.bright ? "#fff" : "#888", dot ? "3" : "1.5");
	}
	fprintf(f, "</g></svg>\n");
	fclose(f);
}

static void run_frame()
{
	coin_sample();
	frame_vecs.clear();
	int budget = CYCLES_PER_FRAME;
	while (!ccpu.waiting)
	{
		int before = ccpu_icount = 0;
		step();
		budget -= (before - ccpu_icount);
		if (budget <= 0) break;   // the frame timer fires even if FRM was not reached
	}
	if (!snap_name.empty()) { write_svg(snap_name); snap_name.clear(); }
	ccpu_wdt_timer_trigger();
	frame_no++;
}

static unsigned rng_state = 1;
static unsigned rnd() { rng_state = rng_state * 1103515245u + 12345u; return (rng_state >> 16) & 0x7fff; }

static int num(const char* s) { return (int)strtol(s, nullptr, 0); }

int main(int argc, char** argv)
{
	if (argc < 4) { fprintf(stderr, "usage: tgtrace rom8k.bin script.txt out.json [svgdir]\n"); return 2; }
	FILE* f = fopen(argv[1], "rb");
	if (!f || fread(rom, 1, sizeof rom, f) != sizeof rom) { fprintf(stderr, "cannot read %s\n", argv[1]); return 1; }
	fclose(f);
	if (argc > 4) svgdir = argv[4];
	machine.gamedrv = &gamedrv;

	MUX_VAL = 0;
	init_ccpu(1, 8);   // JMI reads the joystick comparator; 8K of ROM

	FILE* sc = fopen(argv[2], "r");
	if (!sc) { fprintf(stderr, "cannot read %s\n", argv[2]); return 1; }
	char line[256];
	while (fgets(line, sizeof line, sc))
	{
		char* hash = strchr(line, '#'); if (hash) *hash = 0;
		char cmd[64] = "", a[64] = "", b[64] = "";
		if (sscanf(line, "%63s %63s %63s", cmd, a, b) < 1) continue;
		std::string c = cmd;
		if (c == "frames") { for (int n = num(a); n > 0; n--) run_frame(); }
		else if (c == "coin")
		{
			sw_port &= 0x7f; for (int n = 0; n < 4; n++) run_frame();
			sw_port |= 0x80; for (int n = 0; n < 4; n++) run_frame();
		}
		else if (c == "start")
		{
			in_port &= ~0x80; for (int n = num(a); n > 0; n--) run_frame();
			in_port |= 0x80;
		}
		else if (c == "fire") { if (!strcmp(a, "on")) in_port &= ~0x20; else in_port |= 0x20; }
		else if (c == "shield") { if (!strcmp(a, "on")) in_port &= ~0x40; else in_port |= 0x40; }
		else if (c == "stick") { stick_x = num(a); stick_y = num(b); }
		else if (c == "switches") { sw_port = (UINT8)num(a); }
		else if (c == "snap") { snap_name = a; }
		else if (c == "ram")
		{
			// print all 256 RAM words, labelled, for diffing between script points
			printf("RAM %s frame %ld\n", a, frame_no);
			for (int r = 0; r < 256; r++)
				printf("%03X%s", CCPURAM[r], (r & 15) == 15 ? "\n" : " ");
		}
		else if (c == "autoaim") { aim_pct = num(a); }
		else if (c == "sweep")
		{
			// N frames: the stick traces a slow Lissajous figure, fire pulsed
			int n = num(a);
			for (int k = 0; k < n; k++)
			{
				double t = frame_no / 38.0;
				stick_x = 0x80 + (int)(0x50 * sin(t * 0.9));
				stick_y = 0x80 + (int)(0x50 * sin(t * 1.3 + 1.0));
				if (k % 8 < 4) in_port &= ~0x20; else in_port |= 0x20;
				run_frame();
			}
			in_port |= 0x20;
		}
		else if (c == "random")
		{
			rng_state = (unsigned)num(b);
			int n = num(a);
			int sx = 0x80, sy = 0x80, tx = 0x80, ty = 0x80;
			for (int k = 0; k < n; k++)
			{
				if (rnd() % 40 == 0) { tx = 0x20 + rnd() % 0xc1; ty = 0x20 + rnd() % 0xc1; }
				sx += (tx > sx) ? 4 : (tx < sx) ? -4 : 0;
				sy += (ty > sy) ? 4 : (ty < sy) ? -4 : 0;
				stick_x = sx; stick_y = sy;
				if (rnd() % 6 == 0) in_port ^= 0x20;
				if (rnd() % 90 == 0) in_port &= ~0x40;
				if (rnd() % 15 == 0) in_port |= 0x40;
				run_frame();
			}
			in_port |= 0x60;
		}
		else { fprintf(stderr, "unknown command: %s\n", cmd); return 1; }
	}
	fclose(sc);

	// ---------------------------------------------------------------- report
	FILE* o = fopen(argv[3], "w");
	if (!o) { fprintf(stderr, "cannot write %s\n", argv[3]); return 1; }
	fprintf(o, "{\n\"frames\": %ld,\n\"exec\": [", frame_no);
	bool first = true;
	for (int a = 0; a < 0x2000; a++)
		if (exec_count[a])
		{
			fprintf(o, "%s[%d,%d,%d,%u]", first ? "" : ",", a, pmask[a], accmask[a], exec_count[a]);
			first = false;
		}
	fprintf(o, "],\n\"operand\": [");
	first = true;
	for (int a = 0; a < 0x2000; a++) if (operand[a]) { fprintf(o, "%s%d", first ? "" : ",", a); first = false; }
	fprintf(o, "],\n\"skipped\": [");
	first = true;
	for (int a = 0; a < 0x2000; a++) if (skipped[a]) { fprintf(o, "%s%d", first ? "" : ",", a); first = false; }
	fprintf(o, "]");
	auto dump = [&](const char* name, std::map<int, std::set<int>>& m)
	{
		fprintf(o, ",\n\"%s\": {", name);
		bool f1 = true;
		for (auto& kv : m)
		{
			fprintf(o, "%s\"%d\":[", f1 ? "" : ",", kv.first);
			bool f2 = true;
			for (int v : kv.second) { fprintf(o, "%s%d", f2 ? "" : ",", v); f2 = false; }
			fprintf(o, "]");
			f1 = false;
		}
		fprintf(o, "}");
	};
	dump("jumps", jumps); dump("falls", falls); dump("jvals", jvals); dump("lkp", lkp);
	dump("ram_r", ram_r); dump("ram_w", ram_w); dump("out", outs); dump("inp", inps);
	fprintf(o, ",\n\"ram_vals\": {");
	first = true;
	for (int r = 0; r < 256; r++)
	{
		RamStat& s = ram_stat[r];
		if (!s.writes) continue;
		fprintf(o, "%s\"%d\":[%u,%u,[", first ? "" : ",", r, s.writes, s.changes);
		bool f2 = true;
		for (int v : s.values) { fprintf(o, "%s%d", f2 ? "" : ",", v); f2 = false; }
		fprintf(o, "]]");
		first = false;
	}
	fprintf(o, "}");
	fprintf(o, ",\n\"anomalies\": [");
	first = true;
	for (int a : anomalies) { fprintf(o, "%s%d", first ? "" : ",", a); first = false; }
	fprintf(o, "]\n}\n");
	fclose(o);

	int n = 0;
	for (int a = 0; a < 0x2000; a++) if (exec_count[a]) n++;
	printf("%ld frames, %d opcode addresses executed, %zu anomalies\n", frame_no, n, anomalies.size());
	return 0;
}

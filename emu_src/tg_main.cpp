// Tail Gunner (Cinematronics 1979) test emulator: Windows host.
//
// The CPU is AAE's ccpu.cpp and the vector decoding is AAE's
// cinematronics_video.cpp, both compiled UNMODIFIED from emu_src\cpu\.
// This file is the machine around them: ROM loading, the 38 Hz frame loop,
// the vector display list, input, window / OpenGL / audio plumbing.
//
// The window / input / ini / shot code follows the Tempest emulator's
// plat_win.c (DPI awareness, Alt+Enter fullscreen, raw input, capture).
#include <Windows.h>
#include "glew.h"
#include <mmsystem.h>
#include <dwmapi.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <string>
#include <vector>

extern "C" {
#include "framework.h"
#include "sys_gl.h"
#include "rawinput.h"
}
#include "joystick.h"
#include "mixer.h"
#include "vector_draw.h"
#include "mat4.h"
#include "ini.h"
#include "fileio.h"
#include "monitor_select.h"
#include "tg_emu.h"

#pragma comment(lib, "winmm.lib")
#pragma comment(lib, "dwmapi.lib")
#pragma comment(lib, "user32.lib")
#pragma comment(lib, "gdi32.lib")

#define APP_NAME "Tail Gunner"
#define KEY_HELP "mouse/arrows aim, Ctrl/Space/LMB fire, Alt/Shift/RMB shield, 5 coin, 1 start, " \
                 "P pause, F3 reset, F2 test pattern, F8 mouse capture, Alt+Enter fullscreen, Esc quit"

// ---------------------------------------------------------------- machine
static const int CPU_HZ = 4980750;
static const int FPS = 38;
static const int CYCLES_PER_FRAME = CPU_HZ / FPS;      // 131072
static const int VIS_W = 1024, VIS_H = 768;

static UINT8       rom64k[0x10000];                    // the 8K image, mirrored every 8K
static AaeGameDrv  gamedrv = { FPS, { { CPU_HZ } } };
static AaeDrv      drv = { { 0, VIS_W, 0, VIS_H } };
static AaeMachine  machine;
AaeMachine* Machine = &machine;

extern UINT16 CCPURAM[0x100];                          // ccpu.cpp

// ---------------------------------------------------------------- files
static char exe_dir[MAX_PATH];
static char path_ini[MAX_PATH], path_log[MAX_PATH];

static void resolve_paths(void)
{
	DWORD n = GetModuleFileNameA(NULL, exe_dir, (DWORD)sizeof exe_dir);
	if (n == 0 || n >= sizeof exe_dir) exe_dir[0] = '\0';
	char* slash = strrchr(exe_dir, '\\');
	if (slash) slash[1] = '\0'; else exe_dir[0] = '\0';
	snprintf(path_ini, sizeof path_ini, "%stailgunner_emu.ini", exe_dir);
	snprintf(path_log, sizeof path_log, "%stailgunner_emu.log", exe_dir);
}

static bool file_exists(const char* p)
{
	DWORD a = GetFileAttributesA(p);
	return a != INVALID_FILE_ATTRIBUTES;
}
static bool is_dir(const char* p)
{
	DWORD a = GetFileAttributesA(p);
	return a != INVALID_FILE_ATTRIBUTES && (a & FILE_ATTRIBUTE_DIRECTORY);
}

// ---------------------------------------------------------------- command line
struct ShotReq { int frame; std::string path; };
static std::vector<ShotReq> shot_reqs;
static size_t shots_done;
static bool   hidden_mode, shot_mode, turbo;
static double quit_after_ms;
static int    coin_at = -1, start_at = -1, fire_from = -1, fire_to = -1;
static int    shield_from = -1, shield_to = -1;
static int    script_stick_x = -1, script_stick_y = -1;    // --stick X Y (0x20..0xE0)

// ---------------------------------------------------------------- window state
static HWND hWnd;
static int  g_quit;
static int  paused;
static int  want_reset, want_test;
static int  window_active;
static int  capture_enabled = 1;
static int  is_fullscreen;
static RECT windowed_rect;
static LONG_PTR windowed_style, windowed_exstyle;

extern "C" {
int SCREEN_W = VIS_W;
int SCREEN_H = VIS_H;
int DESIGN_W = VIS_W;
int DESIGN_H = VIS_H;
}

extern "C" HWND win_get_window(void) { return hWnd; }
extern "C" int IsFullscreen(void) { return is_fullscreen; }
extern "C" int KeyCheck(int keynum) { return (keynum >= 0 && keynum < 256) ? key[keynum] : 0; }

static void msg_box(const char* title, const char* message)
{
	LOG_ERROR("%s: %s", title, message);
	if (shot_mode || hidden_mode) return;
	MessageBoxA(NULL, message, title, MB_ICONEXCLAMATION | MB_OK);
}

static double qpc_ms(void)
{
	static LARGE_INTEGER f;
	LARGE_INTEGER c;
	if (!f.QuadPart) QueryPerformanceFrequency(&f);
	QueryPerformanceCounter(&c);
	return (double)c.QuadPart * 1000.0 / (double)f.QuadPart;
}

// ---------------------------------------------------------------- DPI
#ifndef DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2
#define DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 ((DPI_AWARENESS_CONTEXT)-4)
#endif
#ifndef USER_DEFAULT_SCREEN_DPI
#define USER_DEFAULT_SCREEN_DPI 96
#endif
#ifndef WM_DPICHANGED
#define WM_DPICHANGED 0x02E0
#endif

static void enable_dpi_awareness(void)
{
	typedef BOOL(WINAPI* SetCtx_t)(DPI_AWARENESS_CONTEXT);
	HMODULE user32 = GetModuleHandleA("user32.dll");
	if (user32) {
		SetCtx_t set_ctx = (SetCtx_t)(void*)GetProcAddress(user32, "SetProcessDpiAwarenessContext");
		if (set_ctx && set_ctx(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)) return;
	}
	SetProcessDPIAware();
}

static UINT window_dpi(HWND hwnd)
{
	typedef UINT(WINAPI* GetDpi_t)(HWND);
	HMODULE user32 = GetModuleHandleA("user32.dll");
	UINT dpi = 0;
	if (user32) {
		GetDpi_t get_dpi = (GetDpi_t)(void*)GetProcAddress(user32, "GetDpiForWindow");
		if (get_dpi) dpi = get_dpi(hwnd);
	}
	return dpi ? dpi : USER_DEFAULT_SCREEN_DPI;
}

// Client size 1024x768 at the window's DPI, shrunk (keeping 4:3) to 90% of the
// work-area height, then centred in the chosen monitor's work area.
static void size_window(HWND hwnd, DWORD style, const monsel::MonitorDesc& mon)
{
	typedef BOOL(WINAPI* Adjust_t)(LPRECT, DWORD, BOOL, DWORD, UINT);
	UINT dpi = window_dpi(hwnd);
	int cw = MulDiv(DESIGN_W, (int)dpi, USER_DEFAULT_SCREEN_DPI);
	int ch = MulDiv(DESIGN_H, (int)dpi, USER_DEFAULT_SCREEN_DPI);
	int avail_h = (mon.workRect.bottom - mon.workRect.top) * 9 / 10 - 40;
	if (avail_h > 200 && ch > avail_h) { ch = avail_h; cw = ch * 4 / 3; }

	RECT wr = { 0, 0, cw, ch };
	Adjust_t adjust = NULL;
	HMODULE user32 = GetModuleHandleA("user32.dll");
	if (user32) adjust = (Adjust_t)(void*)GetProcAddress(user32, "AdjustWindowRectExForDpi");
	if (adjust) adjust(&wr, style, FALSE, 0, dpi); else AdjustWindowRect(&wr, style, FALSE);

	RECT pos = monsel::CenterInWorkArea(wr.right - wr.left, wr.bottom - wr.top, mon);
	SetWindowPos(hwnd, NULL, pos.left, pos.top, pos.right - pos.left, pos.bottom - pos.top,
		SWP_NOZORDER | SWP_NOACTIVATE);
}

// ---------------------------------------------------------------- fullscreen
extern "C" void ToggleFullscreen(void)
{
	if (is_fullscreen) {
		SetWindowLongPtr(hWnd, GWL_STYLE, windowed_style);
		SetWindowLongPtr(hWnd, GWL_EXSTYLE, windowed_exstyle);
		SetWindowPos(hWnd, HWND_NOTOPMOST, windowed_rect.left, windowed_rect.top,
			windowed_rect.right - windowed_rect.left, windowed_rect.bottom - windowed_rect.top,
			SWP_FRAMECHANGED | SWP_SHOWWINDOW);
		is_fullscreen = 0;
	} else {
		MONITORINFO mi = { sizeof(mi) };
		GetMonitorInfo(MonitorFromWindow(hWnd, MONITOR_DEFAULTTONEAREST), &mi);
		GetWindowRect(hWnd, &windowed_rect);
		windowed_style = GetWindowLongPtr(hWnd, GWL_STYLE);
		windowed_exstyle = GetWindowLongPtr(hWnd, GWL_EXSTYLE);
		SetWindowLongPtr(hWnd, GWL_STYLE, WS_POPUP | WS_VISIBLE);
		SetWindowLongPtr(hWnd, GWL_EXSTYLE, WS_EX_APPWINDOW | WS_EX_TOPMOST);
		SetWindowPos(hWnd, HWND_TOPMOST, mi.rcMonitor.left, mi.rcMonitor.top,
			mi.rcMonitor.right - mi.rcMonitor.left, mi.rcMonitor.bottom - mi.rcMonitor.top,
			SWP_FRAMECHANGED | SWP_SHOWWINDOW);
		is_fullscreen = 1;
	}
}

// ---------------------------------------------------------------- beam width
// [vector] linewidth = beam width in pixels at a 1024-wide window, scaling with
// the picture; line_smoothing = AA feather in physical pixels on any screen.
static float beam_px = 2.0f;
static float beam_feather_px = 1.0f;
static float beam_proj[16];

static void update_beam_width_for(double vw)
{
	const double span = (double)VIS_W;
	if (vw < 1.0) vw = 1.0;
	double feather_du = beam_feather_px * span / vw;
	beam_set_smoothing((float)feather_du);
	double core_px = beam_px - beam_feather_px;
	if (core_px < 0.0) core_px = 0.0;
	beam_set_linewidth((float)(core_px * span / (double)DESIGN_W + feather_du));
}

static void update_beam_width(void)
{
	double vw = (double)SCREEN_W;
	if ((double)SCREEN_H * DESIGN_W < vw * DESIGN_H)
		vw = (double)SCREEN_H * DESIGN_W / (double)DESIGN_H;
	update_beam_width_for(vw);
}

// ---------------------------------------------------------------- mouse capture
static void apply_capture(void)
{
	if (!hWnd) return;
	if (capture_enabled && window_active && !shot_mode && !hidden_mode) {
		RECT rc;
		POINT tl = { 0, 0 }, br;
		GetClientRect(hWnd, &rc);
		br.x = rc.right; br.y = rc.bottom;
		ClientToScreen(hWnd, &tl);
		ClientToScreen(hWnd, &br);
		rc.left = tl.x; rc.top = tl.y; rc.right = br.x; rc.bottom = br.y;
		ClipCursor(&rc);
	} else {
		ClipCursor(NULL);
	}
}

// ---------------------------------------------------------------- vector display
// The AAE vector list: points added by cinemat_vector_callback (16.16 coords).
// A point with intensity > 0 and colour != 0 draws a line from the previous
// point (mame_vector.cpp vector_add_point / vector_update).
struct VPoint { int x, y; unsigned col; int intensity; };
static const int MAX_POINTS = 65536;
static VPoint vlist[MAX_POINTS];
static int    vcount;
static bool   vwarned;

void vector_clear_list() { vcount = 0; }

void vector_add_point(int x, int y, unsigned int color, int intensity)
{
	if (intensity > 0x1000) intensity >>= 8;     // AAE's textured-shot overload, unused here
	if (intensity > 0xff) intensity = 0xff;
	if (vcount >= MAX_POINTS) {
		if (!vwarned) { vwarned = true; LOG_WARN("vector list overflow"); }
		return;
	}
	vlist[vcount].x = x;
	vlist[vcount].y = y;
	vlist[vcount].col = color;
	vlist[vcount].intensity = intensity;
	vcount++;
}

struct Seg { float x0, y0, x1, y1; int intensity; unsigned col; };
static std::vector<Seg> frame_segs;

static void capture_segments(void)
{
	frame_segs.clear();
	int lastx = 0, lasty = 0;
	for (int i = 0; i < vcount; i++) {
		const VPoint& p = vlist[i];
		if (p.intensity != 0 && p.col) {
			Seg s;
			s.x0 = (float)lastx / 65536.0f;
			s.y0 = (float)lasty / 65536.0f;
			s.x1 = (float)p.x / 65536.0f;
			s.y1 = (float)p.y / 65536.0f;
			s.intensity = p.intensity;
			s.col = p.col;
			frame_segs.push_back(s);
		}
		lastx = p.x;
		lasty = p.y;
	}
}

static void draw_frame(void)
{
	beam_clear();
	for (const Seg& s : frame_segs)
		beam_add_line(s.x0, s.y0, s.x1 + .00001f, s.y1 + .00001f, s.intensity, s.col);
	beam_draw_all(beam_proj);
}

static void present(void)
{
	glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
	glClear(GL_COLOR_BUFFER_BIT);
	draw_frame();
	glSwap();
}

// ---------------------------------------------------------------- screenshots
static int write_bmp(const char* path, const uint8_t* rgb_bottom_up, int w, int h)
{
	int pad = (4 - (w * 3) % 4) % 4;
	uint32_t data = (uint32_t)((w * 3 + pad) * h);
	uint8_t hdr[54];
	memset(hdr, 0, sizeof hdr);
	hdr[0] = 'B'; hdr[1] = 'M';
	auto put32 = [&](int o, uint32_t v) {
		hdr[o] = (uint8_t)v; hdr[o + 1] = (uint8_t)(v >> 8); hdr[o + 2] = (uint8_t)(v >> 16); hdr[o + 3] = (uint8_t)(v >> 24);
	};
	put32(2, 54u + data);
	put32(10, 54u);
	put32(14, 40u);
	put32(18, (uint32_t)w);
	put32(22, (uint32_t)h);
	hdr[26] = 1; hdr[28] = 24;
	put32(34, data);
	FILE* f = fopen(path, "wb");
	if (!f) return 1;
	fwrite(hdr, 1, sizeof hdr, f);
	for (int y = 0; y < h; y++) {
		const uint8_t* row = rgb_bottom_up + (size_t)y * (size_t)w * 3u;
		for (int x = 0; x < w; x++) {
			uint8_t px[3] = { row[x * 3 + 2], row[x * 3 + 1], row[x * 3] };
			fwrite(px, 1, 3, f);
		}
		if (pad) { static const uint8_t z[3] = { 0, 0, 0 }; fwrite(z, 1, (size_t)pad, f); }
	}
	fclose(f);
	return 0;
}

static int save_shot(const char* path)
{
	const int shot_w = VIS_W, shot_h = VIS_H;
	GLuint fbo = 0, rb = 0;
	int rc = 1;
	std::vector<uint8_t> buf((size_t)shot_w * shot_h * 3);
	glGenFramebuffers(1, &fbo);
	glBindFramebuffer(GL_FRAMEBUFFER, fbo);
	glGenRenderbuffers(1, &rb);
	glBindRenderbuffer(GL_RENDERBUFFER, rb);
	glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8, shot_w, shot_h);
	glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, rb);
	if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
		LOG_ERROR("shot: framebuffer incomplete");
	} else {
		glViewport(0, 0, shot_w, shot_h);
		update_beam_width_for((double)shot_w);
		glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
		glClear(GL_COLOR_BUFFER_BIT);
		draw_frame();
		glFinish();
		glPixelStorei(GL_PACK_ALIGNMENT, 1);
		glReadPixels(0, 0, shot_w, shot_h, GL_RGB, GL_UNSIGNED_BYTE, buf.data());
		rc = write_bmp(path, buf.data(), shot_w, shot_h);
	}
	glBindFramebuffer(GL_FRAMEBUFFER, 0);
	glDeleteRenderbuffers(1, &rb);
	glDeleteFramebuffers(1, &fbo);
	ViewOrthoScaled(SCREEN_W, SCREEN_H, DESIGN_W, DESIGN_H);
	update_beam_width();
	return rc;
}

// ---------------------------------------------------------------- window procedure
static LRESULT CALLBACK WndProc(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam)
{
	switch (message) {
	case WM_SIZE:
		if (wParam != SIZE_MINIMIZED) {
			SCREEN_W = LOWORD(lParam);
			SCREEN_H = HIWORD(lParam);
			if (SCREEN_W > 0 && SCREEN_H > 0) {
				ViewOrthoScaled(SCREEN_W, SCREEN_H, DESIGN_W, DESIGN_H);
				update_beam_width();
			}
			apply_capture();
		}
		return 0;

	case WM_MOVE:
		apply_capture();
		return 0;

	case WM_DPICHANGED: {
		const RECT* r = (const RECT*)lParam;
		SetWindowPos(hwnd, NULL, r->left, r->top, r->right - r->left, r->bottom - r->top,
			SWP_NOZORDER | SWP_NOACTIVATE);
		return 0;
	}

	case WM_ACTIVATE:
		window_active = LOWORD(wParam) != WA_INACTIVE;
		if (!window_active) memset(key, 0, sizeof key);   // no stuck keys
		apply_capture();
		return 0;

	case WM_SYSKEYDOWN:
		if (wParam == VK_RETURN && (lParam & (1 << 29))) {   // Alt+Enter
			ToggleFullscreen();
			key[KEY_ENTER] = 0;
			return 0;
		}
		return DefWindowProcA(hwnd, message, wParam, lParam);

	case WM_ERASEBKGND:
		return 1;

	case WM_PAINT:
		ValidateRect(hwnd, NULL);
		return 0;

	case WM_SYSCOMMAND:
		// a lone Alt (shield) release would open the window menu's modal loop
		if ((wParam & 0xFFF0) == SC_KEYMENU) return 0;
		return DefWindowProcA(hwnd, message, wParam, lParam);

	case WM_SETCURSOR:
		if (LOWORD(lParam) == HTCLIENT && (is_fullscreen || (capture_enabled && window_active))) {
			SetCursor(NULL);
			return 1;
		}
		return DefWindowProcA(hwnd, message, wParam, lParam);

	case WM_CLOSE:
		LOG_INFO("quit: window closed (WM_CLOSE)");
		g_quit = 1;
		return 0;

	case WM_INPUT:
		RawInput_ProcessInput(hwnd, wParam, lParam);
		return DefWindowProcA(hwnd, message, wParam, lParam);

	case WM_DEVICECHANGE:
		joystick_device_change();
		return DefWindowProcA(hwnd, message, wParam, lParam);

	case WM_DESTROY:
		return 0;

	case WM_KEYDOWN:
		if (wParam == VK_ESCAPE) { LOG_INFO("quit: Esc"); g_quit = 1; return 0; }
		if (!(lParam & (1 << 30))) {
			if (wParam == 'P') { paused = !paused; LOG_INFO("pause %s", paused ? "on" : "off"); }
			else if (wParam == VK_F3) want_reset = 1;
			else if (wParam == VK_F2) want_test = 1;
			else if (wParam == VK_F8) {
				capture_enabled = !capture_enabled;
				LOG_INFO("mouse capture %s (F8)", capture_enabled ? "on" : "off");
				apply_capture();
			}
		}
		return 0;

	default:
		return DefWindowProcA(hwnd, message, wParam, lParam);
	}
}

static void pump_messages(void)
{
	MSG msg;
	while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) {
		if (msg.message == WM_QUIT) { g_quit = 1; break; }
		TranslateMessage(&msg);
		DispatchMessageA(&msg);
	}
}

// ---------------------------------------------------------------- ROMs
static uint32_t crc32_of(const UINT8* d, size_t n)
{
	uint32_t c = 0xFFFFFFFFu;
	for (size_t i = 0; i < n; i++) {
		c ^= d[i];
		for (int k = 0; k < 8; k++) c = (c >> 1) ^ (0xEDB88320u & (0u - (c & 1u)));
	}
	return ~c;
}

// Loads the four 2K chips from a zip or a directory. 1 on success.
static bool load_chips(const std::string& where, UINT8* chips[4])
{
	static const char* const names[4] = { "tgunner.t70", "tgunner.p70", "tgunner.t71", "tgunner.p71" };
	bool zip = !is_dir(where.c_str());
	if (zip && !file_exists(where.c_str())) return false;
	for (int i = 0; i < 4; i++) {
		unsigned char* b;
		size_t sz;
		if (zip) {
			b = loadGenericZip(where.c_str(), names[i]);
			sz = getlastZsize();
		} else {
			std::string p = where;
			if (!p.empty() && p.back() != '\\' && p.back() != '/') p += '\\';
			p += names[i];
			b = load_file(p.c_str());
			sz = (size_t)getLastFileSize();
		}
		if (!b || sz != 2048) {
			if (b) free(b);
			for (int j = 0; j < i; j++) { free(chips[j]); chips[j] = NULL; }
			return false;
		}
		chips[i] = b;
	}
	return true;
}

static bool load_roms(const char* ini_override)
{
	std::vector<std::string> cand;
	if (ini_override && ini_override[0]) cand.push_back(ini_override);
	std::string e = exe_dir;
	cand.push_back(e + "roms\\tailg.zip");
	cand.push_back(e + "roms\\tailg");
	cand.push_back(e + "..\\roms\\tailg.zip");
	cand.push_back(e + "..\\roms\\tailg");

	UINT8* chips[4] = { 0, 0, 0, 0 };
	std::string used;
	for (const std::string& c : cand) {
		if (load_chips(c, chips)) { used = c; break; }
		LOG_INFO("roms: not usable: %s", c.c_str());
	}
	if (used.empty()) return false;

	UINT8 img[0x2000];
	for (int i = 0; i < 2048; i++) {
		img[2 * i] = chips[0][i];            // t70 = even bytes
		img[2 * i + 1] = chips[1][i];        // p70 = odd bytes
		img[0x1000 + 2 * i] = chips[2][i];   // t71
		img[0x1000 + 2 * i + 1] = chips[3][i]; // p71
	}
	for (int i = 0; i < 4; i++) free(chips[i]);
	for (int a = 0; a < 0x10000; a++) rom64k[a] = img[a & 0x1fff];
	LOG_INFO("roms: loaded from %s, 8K image CRC32 %08X", used.c_str(), crc32_of(img, sizeof img));
	return true;
}

// ---------------------------------------------------------------- DIP switches
static std::string cfg_str(const char* sec, const char* key_, const char* def)
{
	char* s = get_config_string(sec, key_, def);
	std::string r = s ? s : def;
	free(s);
	return r;
}

static UINT8 read_dips(void)
{
	static const char* const sp_n[] = { "15", "20", "30", "40", "50", "60", "70", "80" };
	static const UINT8       sp_v[] = { 0x00, 0x02, 0x01, 0x03, 0x20, 0x22, 0x21, 0x23 };
	static const char* const co_n[] = { "1C1C", "2C1C" };
	static const UINT8       co_v[] = { 0x04, 0x00 };
	UINT8 dip = 0;

	std::string s = cfg_str("dips", "shield_points", "80");
	int pick = 7;
	for (int i = 0; i < 8; i++) if (_stricmp(s.c_str(), sp_n[i]) == 0) pick = i;
	set_config_string("dips", "shield_points", sp_n[pick]);
	dip |= sp_v[pick];

	s = cfg_str("dips", "coinage", "1C1C");
	pick = 0;
	for (int i = 0; i < 2; i++) if (_stricmp(s.c_str(), co_n[i]) == 0) pick = i;
	set_config_string("dips", "coinage", co_n[pick]);
	dip |= co_v[pick];

	static const struct { const char* name; UINT8 bit; } unk[3] = { { "unknown_08", 0x08 }, { "unknown_10", 0x10 }, { "unknown_40", 0x40 } };
	for (int i = 0; i < 3; i++) {
		s = cfg_str("dips", unk[i].name, "off");
		bool on = _stricmp(s.c_str(), "on") == 0;
		set_config_string("dips", unk[i].name, on ? "on" : "off");
		if (!on) dip |= unk[i].bit;        // switch OFF = bit set (the driver's default)
	}
	LOG_INFO("dips: SWITCHES bits 0-6 = %02X", dip);
	return dip;
}

// ---------------------------------------------------------------- input
static float  mouse_sens = 0.15f;          // stick units per mickey
static float  key_rate = 120.0f;           // stick units per second
static int    invert_y;
static float  stick_fx = 128.0f, stick_fy = 128.0f;
static int    coin_hold;                   // frames the coin switch stays closed
static int    joy_was_active;
static int    force_start_frames;          // F2: START held after a reset

static float clampf(float v, float lo, float hi) { return v < lo ? lo : v > hi ? hi : v; }

static void poll_input(long frame)
{
	int fire = 0, shield = 0, start = 0, coin = 0;

	if (!hidden_mode && !shot_mode) {
		int mx = 0, my = 0;
		get_mouse_mickeys(&mx, &my);
		if (window_active) {
			// Up on the screen is a HIGHER analog Y value (see report: READAXIS /
			// JOYSTICK in the listing), and mouse-up is a negative mickey.
			float ysign = invert_y ? 1.0f : -1.0f;
			stick_fx += (float)mx * mouse_sens;
			stick_fy += (float)my * mouse_sens * ysign;
			float step = key_rate / (float)FPS;
			if (key[KEY_RIGHT]) stick_fx += step;
			if (key[KEY_LEFT])  stick_fx -= step;
			if (key[KEY_UP])    stick_fy += invert_y ? -step : step;
			if (key[KEY_DOWN])  stick_fy -= invert_y ? -step : step;

			fire   = key[KEY_LCONTROL] || key[KEY_RCONTROL] || key[KEY_SPACE] || (mouse_b & 1);
			shield = key[KEY_ALT] || key[KEY_RMENU] || key[KEY_LSHIFT] || key[KEY_RSHIFT] || (mouse_b & 2);
			start  = key[KEY_1];
			if (key[KEY_5] || key[KEY_3]) coin_hold = 3;
		}

		poll_joystick();
		if (num_joysticks > 0 && joystick_is_connected(0)) {
			int ax = joy_x, ay = joy_y;
			if (ax != 0 || ay != 0) {
				// absolute: the (dead-zoned) stick maps onto the analog range
				stick_fx = 128.0f + (float)ax * (96.0f / 128.0f);
				stick_fy = 128.0f + (float)(invert_y ? ay : -ay) * (96.0f / 128.0f);
				joy_was_active = 1;
			} else if (joy_was_active) {
				stick_fx = stick_fy = 128.0f;
				joy_was_active = 0;
			}
			if (joy[0].num_buttons > 0 && joy[0].button[0].b) fire = 1;
			if (joy[0].num_buttons > 1 && joy[0].button[1].b) shield = 1;
			if (joy[0].num_buttons > 6 && joy[0].button[6].b) coin_hold = 3;
			if (joy[0].num_buttons > 7 && joy[0].button[7].b) start = 1;
		}
	}

	// scripted input (--coin-at / --start-at / --fire)
	if (coin_at >= 0 && frame >= coin_at && frame < coin_at + 3) coin = 1;
	if (start_at >= 0 && frame >= start_at && frame < start_at + 4) start = 1;
	if (fire_from >= 0 && frame >= fire_from && frame < fire_to) fire = 1;

	if (shield_from >= 0 && frame >= shield_from && frame < shield_to) shield = 1;
	if (script_stick_x >= 0) { stick_fx = (float)script_stick_x; stick_fy = (float)script_stick_y; }

	if (force_start_frames > 0) { start = 1; force_start_frames--; }
	if (coin_hold > 0) { coin = 1; coin_hold--; }

	stick_fx = clampf(stick_fx, 0x20, 0xe0);
	stick_fy = clampf(stick_fy, 0x20, 0xe0);

	tg_board_set_stick((int)(stick_fx + 0.5f), (int)(stick_fy + 0.5f));
	tg_board_set_buttons(fire, shield, start);
	tg_board_set_coin(coin);
}

// ---------------------------------------------------------------- command line
static void parse_command_line(void)
{
	for (int i = 1; i < __argc; i++) {
		const char* a = __argv[i];
		auto num = [&](int k) { return (i + k < __argc) ? atoi(__argv[i + k]) : 0; };
		if (!strcmp(a, "--hidden")) hidden_mode = true;
		else if (!strcmp(a, "--turbo")) turbo = true;
		else if (!strcmp(a, "--quit-after-ms")) { quit_after_ms = num(1); i++; }
		else if (!strcmp(a, "--shot") && i + 2 < __argc) {
			shot_reqs.push_back({ num(1), __argv[i + 2] });
			shot_mode = true;
			i += 2;
		}
		else if (!strcmp(a, "--coin-at")) { coin_at = num(1); i++; }
		else if (!strcmp(a, "--start-at")) { start_at = num(1); i++; }
		else if (!strcmp(a, "--fire")) { fire_from = num(1); fire_to = num(2); i += 2; }
		else if (!strcmp(a, "--shield")) { shield_from = num(1); shield_to = num(2); i += 2; }
		else if (!strcmp(a, "--stick")) { script_stick_x = num(1); script_stick_y = num(2); i += 2; }
	}
	if (shot_mode) { hidden_mode = true; turbo = true; }
}

// ---------------------------------------------------------------- reset
static void machine_reset(bool hold_start)
{
	ccpu_reset();
	tg_board_init();
	tg_sound_reset();
	if (hold_start) force_start_frames = 2 * FPS;
}

// ---------------------------------------------------------------- WinMain
int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE, LPSTR, int)
{
	parse_command_line();
	resolve_paths();
	log_open(path_log);
	log_set_level(LOG_LEVEL_INFO);
	LOG_INFO("tailgunner_emu starting%s%s", hidden_mode ? " (hidden)" : "", shot_mode ? " (shot mode: turbo, no audio)" : "");

	enable_dpi_awareness();
	set_config_file(path_ini);

	// ---- ini
	std::string roms_override = cfg_str("main", "roms", "");
	set_config_string("main", "roms", roms_override.c_str());
	int swap_mode = get_config_int("main", "vsync", 0);
	set_config_int("main", "vsync", swap_mode);
	int start_mon = get_config_int("main", "starting_monitor", 1);
	set_config_int("main", "starting_monitor", start_mon);
	std::string start_mon_id = cfg_str("main", "starting_monitor_id", "");
	set_config_string("main", "starting_monitor_id", start_mon_id.c_str());

	UINT8 dips = read_dips();

	beam_px = get_config_float("vector", "linewidth", 2.0f);
	beam_feather_px = get_config_float("vector", "line_smoothing", 1.0f);
	if (beam_px < 0.1f) beam_px = 0.1f;
	if (beam_feather_px < 0.0f) beam_feather_px = 0.0f;
	set_config_float("vector", "linewidth", beam_px);
	set_config_float("vector", "line_smoothing", beam_feather_px);

	mouse_sens = get_config_float("input", "mouse_sensitivity", 0.15f);
	set_config_float("input", "mouse_sensitivity", mouse_sens);
	key_rate = get_config_float("input", "key_rate", 120.0f);
	set_config_float("input", "key_rate", key_rate);
	invert_y = get_config_int("input", "invert_y", 0) != 0;
	set_config_int("input", "invert_y", invert_y);
	capture_enabled = get_config_int("input", "mouse_capture", 1) != 0;
	set_config_int("input", "mouse_capture", capture_enabled);

	int deadzone = get_config_int("joystick", "deadzone", 19);
	set_config_int("joystick", "deadzone", deadzone);

	int volume = get_config_int("sound", "volume", 80);
	if (volume < 0) volume = 0;
	if (volume > 100) volume = 100;
	set_config_int("sound", "volume", volume);
	std::string samples_override = cfg_str("sound", "samples", "");
	set_config_string("sound", "samples", samples_override.c_str());

	// ---- ROMs
	if (!load_roms(roms_override.c_str())) {
		msg_box(APP_NAME, "Could not find the Tail Gunner ROMs (tgunner.t70 .p70 .t71 .p71).\n"
			"Put them in roms\\tailg.zip or roms\\tailg\\ beside the exe (or in ..\\roms), "
			"or set [main] roms= in tailgunner_emu.ini.");
		log_close();
		return 1;
	}

	// ---- window
	WNDCLASSA wc;
	memset(&wc, 0, sizeof wc);
	wc.style = CS_OWNDC;
	wc.lpfnWndProc = WndProc;
	wc.hInstance = hInstance;
	wc.hIcon = LoadIcon(NULL, IDI_APPLICATION);
	wc.hCursor = LoadCursor(NULL, IDC_ARROW);
	wc.hbrBackground = (HBRUSH)GetStockObject(BLACK_BRUSH);
	wc.lpszClassName = "TailgunnerEmu";
	if (!RegisterClassA(&wc)) { msg_box(APP_NAME, "Failed to register the window class."); return 1; }

	std::string reason;
	monsel::MonitorDesc mon = monsel::Select(start_mon, start_mon_id, &reason);
	LOG_INFO("monitor: %s", reason.c_str());
	LOG_INFO("monitors:\n%s", monsel::DescribeAll().c_str());

	DWORD style = WS_CAPTION | WS_POPUPWINDOW | WS_CLIPSIBLINGS | WS_CLIPCHILDREN
		| WS_SYSMENU | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_THICKFRAME;
	hWnd = CreateWindowA("TailgunnerEmu", APP_NAME, style,
		mon.workRect.left + 40, mon.workRect.top + 40, 1040, 800, NULL, NULL, hInstance, NULL);
	if (!hWnd) { msg_box(APP_NAME, "Failed to create the main window."); return 1; }
	if (!hidden_mode) size_window(hWnd, style, mon);
	if (hidden_mode) { SCREEN_W = VIS_W; SCREEN_H = VIS_H; }

	if (FAILED(RawInput_Initialize(hWnd)))
		LOG_ERROR("RawInput_Initialize failed");
	set_config_int("joystick", "deadzone", deadzone);
	install_joystick();
	joystick_set_deadzone(deadzone);

	// audio: not in --hidden / --shot runs (sample_start calls are still counted)
	int mixer_ok = 0;
	if (!hidden_mode && !shot_mode && volume > 0) {
		if (mixer_init() == 0) { mixer_ok = 1; mixer_set_master_volume(volume); }
		else LOG_ERROR("mixer_init failed; running silent");
	}
	tg_sound_set_active(mixer_ok);
	{
		std::string zip;
		if (!samples_override.empty()) zip = samples_override;
		else {
			std::string e = exe_dir;
			const char* cand[] = { "samples\\tailg.zip", "tailg.zip", "..\\samples\\tailg.zip" };
			for (const char* c : cand) if (file_exists((e + c).c_str())) { zip = e + c; break; }
		}
		if (zip.empty() || !file_exists(zip.c_str())) {
			LOG_WARN("sound: tailg.zip samples not found; running silent");
			zip.clear();
		} else LOG_INFO("sound: samples from %s", zip.c_str());
		tg_sound_load(zip.c_str());
	}

	if (!CreateGLContext()) { msg_box(APP_NAME, "Failed to create an OpenGL context."); return 1; }
	swap_mode = SetSwapMode(shot_mode ? 0 : swap_mode);
	ViewOrthoScaled(SCREEN_W, SCREEN_H, DESIGN_W, DESIGN_H);
	if (!beam_init()) { msg_box(APP_NAME, "Beam renderer failed to build (needs OpenGL 3.3) - see tailgunner_emu.log."); return 1; }
	beam_set_color_mode(0);                       // B/W game: sorted alpha-over
	update_beam_width();
	mat4_ortho(beam_proj, 0.0f, (float)VIS_W, 0.0f, (float)VIS_H, -1.0f, 1.0f);   // game Y grows upward
	LOG_INFO("beam: %.2f px wide at a %d-wide window, %.2f px feather; swap mode %d", beam_px, DESIGN_W, beam_feather_px, swap_mode);

	timeBeginPeriod(1);
	if (!hidden_mode) {
		SetWindowTextA(hWnd, APP_NAME " - " KEY_HELP);
		ShowWindow(hWnd, SW_SHOW);
		SetForegroundWindow(hWnd);
		window_active = GetForegroundWindow() == hWnd;
		apply_capture();
	}

	// ---- machine
	machine.memory_region[0] = rom64k;
	machine.gamedrv = &gamedrv;
	machine.drv = &drv;
	video_type_set(COLOR_BILEVEL, 0);
	tg_board_init();
	tg_board_set_dips(dips);
	tg_sound_reset();
	init_ccpu(1, 8);                              // JMI reads joystick_read; 8K ROM

	// ---- frame loop
	const double period = 1000.0 / (double)FPS;
	const double t_start = qpc_ms();
	double next_ms = t_start;
	long frame = 0;
	unsigned long long total_segs = 0;
	size_t min_segs = (size_t)-1, max_segs = 0;
	double last_log_ms = t_start;
	long last_log_frame = 0;

	while (!g_quit) {
		pump_messages();
		if (g_quit) break;
		double now = qpc_ms();
		if (quit_after_ms > 0.0 && now - t_start >= quit_after_ms) { LOG_INFO("quit: --quit-after-ms"); break; }

		if (paused) {
			if (!hidden_mode) present();
			Sleep(15);
			next_ms = qpc_ms();
			continue;
		}
		if (!turbo) {
			if (now < next_ms) { if (next_ms - now > 1.5) Sleep(1); continue; }
			next_ms += period;
			if (now - next_ms > 5.0 * period) next_ms = now + period;   // fell far behind: resync
		}

		if (want_reset || want_test) {
			bool test = want_test != 0;
			want_reset = want_test = 0;
			LOG_INFO("reset (%s)", test ? "F2: START held 2 s, test pattern" : "F3");
			machine_reset(test);
			tg_board_set_dips(dips);
			if (mixer_ok) samples_stop_all();
		}

		poll_input(frame);
		run_ccpu(CYCLES_PER_FRAME);
		capture_segments();
		frame++;

		size_t ns = frame_segs.size();
		total_segs += ns;
		if (ns < min_segs) min_segs = ns;
		if (ns > max_segs) max_segs = ns;

		if (!hidden_mode) present();

		for (; shots_done < shot_reqs.size() && shot_reqs[shots_done].frame <= frame; shots_done++) {
			int rc = save_shot(shot_reqs[shots_done].path.c_str());
			size_t bright = 0;
			for (const Seg& s : frame_segs) if (RGB_RED(s.col) > 0xc0) bright++;
			LOG_INFO("shot: frame %ld -> %s (%s), %zu segments (%zu bright, %zu dim), credits word %03X",
				frame, shot_reqs[shots_done].path.c_str(), rc ? "FAILED" : "ok", ns, bright, ns - bright, CCPURAM[0x89]);
		}

		coin_sample();
		cinevid_update();                          // = ccpu_wdt_timer_trigger

		if (now - last_log_ms >= 5000.0) {
			double dt = (now - last_log_ms) / 1000.0;
			LOG_INFO("frame %ld: %.2f fps over the last %.1f s, %zu segments, credits %03X, waiting %d",
				frame, (double)(frame - last_log_frame) / dt, dt, ns, CCPURAM[0x89], ccpu_is_waiting());
			last_log_ms = now;
			last_log_frame = frame;
		}
		if (shot_mode && shots_done >= shot_reqs.size()) { LOG_INFO("quit: all shots taken"); break; }
	}

	// ---- shutdown
	double elapsed = (qpc_ms() - t_start) / 1000.0;
	LOG_INFO("ran %ld frames in %.2f s = %.2f fps; segments/frame avg %.1f min %zu max %zu",
		frame, elapsed, elapsed > 0 ? frame / elapsed : 0.0,
		frame ? (double)total_segs / (double)frame : 0.0, frame ? min_segs : 0, max_segs);
	tg_sound_log_stats();
	ClipCursor(NULL);
	timeEndPeriod(1);
	tg_sound_shutdown();
	beam_shutdown();
	remove_joystick();
	mixer_end();
	DeleteGLContext();
	LOG_INFO("tailgunner_emu closing");
	log_close();
	if (IsWindow(hWnd)) DestroyWindow(hWnd);
	return 0;
}

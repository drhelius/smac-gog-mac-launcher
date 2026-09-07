/* MIT License. In-memory movie redirection for the two hash-verified GOG executables.
 * Movie function locations were identified in PRACX and checked against our binaries.
 * No proprietary game instructions or assets are distributed in this file.
 */
#include "win32_minimal.h"

static const char request_path[] = "centauri-movie.request";
static const char done_path[] = "centauri-movie.done";
static HWND game_window;
static WNDPROC game_window_proc;
static int window_width = 1024;
static int window_height = 768;

static DWORD decorated_style(DWORD style)
{
    return (style & ~(0x80000000u | 0x01000000u | 0x00040000u | 0x00010000u)) |
           0x00c00000u | 0x00080000u | 0x00020000u;
}

static LONG WINAPI window_proc(HWND window, unsigned int message, DWORD wparam, LONG lparam)
{
    if ((message >= 0x0083 && message <= 0x0086) || message == 0x0112)
        return DefWindowProcA(window, message, wparam, lparam);
    return CallWindowProcA(game_window_proc, window, message, wparam, lparam);
}

static HWND WINAPI create_window(DWORD extended, const char* class_name, const char* title, DWORD style,
                                int x, int y, int width, int height, HWND parent, HANDLE menu,
                                HMODULE instance, void* parameter)
{
    BOOL main_window = !game_window && !parent && (style & 0x80000000u) && width >= 640 && height >= 400;
    if (main_window)
    {
        RECT rectangle = { 0, 0, window_width, window_height };
        style = decorated_style(style);
        extended &= ~0x8u;
        AdjustWindowRectEx(&rectangle, style, menu != 0, extended);
        width = rectangle.right - rectangle.left;
        height = rectangle.bottom - rectangle.top;
        x = (GetSystemMetrics(0) - width) / 2;
        y = (GetSystemMetrics(1) - height) / 2;
        if (x < 20) x = 20;
        if (y < 50) y = 50;
    }
    HWND result = CreateWindowExA(extended, class_name, title, style, x, y, width, height, parent, menu, instance, parameter);
    if (main_window && result)
    {
        game_window = result;
        SetWindowLongA(result, -16, (LONG)decorated_style((DWORD)GetWindowLongA(result, -16)));
        SetWindowLongA(result, -20, GetWindowLongA(result, -20) & ~0x8);
        game_window_proc = (WNDPROC)SetWindowLongA(result, -4, (LONG)window_proc);
        SetWindowPos(result, (HWND)-2, x, y, width, height, 0x0020 | 0x0010);
    }
    return result;
}

static int WINAPI system_metrics(int index)
{
    if (index == 0) return window_width;
    if (index == 1) return window_height;
    return GetSystemMetrics(index);
}

static BOOL WINAPI cursor_position(POINT* point)
{
    if (!GetCursorPos(point)) return 0;
    if (game_window)
    {
        if (!ScreenToClient(game_window, point)) return 0;
        return point->x >= 0 && point->y >= 0 && point->x < window_width && point->y < window_height;
    }
    return 1;
}

static BOOL WINAPI set_cursor_position(int x, int y)
{
    POINT point = { x, y };
    if (game_window) ClientToScreen(game_window, &point);
    return SetCursorPos(point.x, point.y);
}

static LONG WINAPI set_window_long(HWND window, int index, LONG value)
{
    if (window == game_window)
    {
        if (index == -16) value = (LONG)decorated_style((DWORD)value);
        if (index == -20) value &= ~0x8;
        if (index == -4)
        {
            LONG old = (LONG)game_window_proc;
            game_window_proc = (WNDPROC)value;
            return old;
        }
    }
    return SetWindowLongA(window, index, value);
}

static BOOL same_text(const char* left, const char* right)
{
    while (*left && *left == *right) { left++; right++; }
    return *left == *right;
}

static BOOL hook_import(BYTE* base, const char* name, void* replacement)
{
    DWORD pe = *(DWORD*)(base + 60);
    DWORD* descriptor = (DWORD*)(base + *(DWORD*)(base + pe + 24 + 104));
    for (unsigned int library = 0; library < 128 && descriptor[3]; library++, descriptor += 5)
    {
        if (!descriptor[0]) continue;
        DWORD* names = (DWORD*)(base + descriptor[0]);
        DWORD* addresses = (DWORD*)(base + descriptor[4]);
        for (unsigned int index = 0; index < 1024 && names[index]; index++)
        {
            if (!(names[index] & 0x80000000u) && same_text((const char*)(base + names[index] + 2), name))
            {
                DWORD protection, ignored;
                if (!VirtualProtect(addresses + index, 4, 0x04, &protection)) return 0;
                addresses[index] = (DWORD)replacement;
                VirtualProtect(addresses + index, 4, protection, &ignored);
                return 1;
            }
        }
    }
    return 0;
}

static int environment_number(const char* name, int fallback)
{
    char buffer[16];
    DWORD length = GetEnvironmentVariableA(name, buffer, sizeof(buffer));
    if (!length || length >= sizeof(buffer)) return fallback;
    int value = 0;
    for (DWORD i = 0; i < length; i++)
    {
        if (buffer[i] < '0' || buffer[i] > '9') return fallback;
        value = value * 10 + buffer[i] - '0';
        if (value > 4096) return fallback;
    }
    return value;
}

static void __cdecl show_movie(const char* filename)
{
    char name[128];
    DWORD written;
    DWORD start;
    unsigned int length = 0;
    const char* base = filename;
    HWND window;
    HANDLE file;

    if (!filename) return;
    for (const char* p = filename; *p; p++)
    {
        if (*p == '\\' || *p == '/') base = p + 1;
    }
    for (const char* p = base; *p && length < sizeof(name) - 5; p++)
    {
        char c = *p;
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
              (c >= '0' && c <= '9') || c == '_' || c == '-' || c == '.' || c == ' ')) return;
        name[length++] = c;
    }
    if (!length || length >= sizeof(name) - 5) return;
    if (!(length > 4 && name[length - 4] == '.'))
    {
        name[length++] = '.';
        name[length++] = 'w';
        name[length++] = 'v';
        name[length++] = 'e';
    }
    name[length] = 0;
    DeleteFileA(done_path);
    file = CreateFileA("centauri-movie.tmp", 0x40000000, 0, 0, 2, 0x80, 0);
    if (file == INVALID_HANDLE_VALUE) return;
    BOOL ok = WriteFile(file, name, length, &written, 0);
    CloseHandle(file);
    if (!ok || written != length) return;
    if (!MoveFileExA("centauri-movie.tmp", request_path, 0x1 | 0x8)) return;

    window = GetActiveWindow();
    start = GetTickCount();
    // The launcher acknowledges every request, including failed conversions. Its Stop action kills this prefix.
    while (GetFileAttributesA(done_path) == 0xffffffff && GetTickCount() - start < 900000)
    {
        Sleep(50);
    }
    DeleteFileA(done_path);
    if (window)
    {
        SetForegroundWindow(window);
        InvalidateRect(window, 0, 1);
    }
}

static BOOL matches(const BYTE* memory, const BYTE* expected, unsigned int count)
{
    for (unsigned int i = 0; i < count; i++)
    {
        if (memory[i] != expected[i]) return 0;
    }
    return 1;
}

__declspec(dllexport) void __cdecl Initialize(void) {}

BOOL WINAPI DllMain(HMODULE module, DWORD reason, void* reserved)
{
    static const BYTE base_prologue[] = { 0x6a, 0xff, 0x64, 0xa1, 0x00 };
    static const BYTE crossfire_prologue[] = { 0x55, 0x8b, 0xec, 0x64, 0xa1 };
    static const BYTE destructor_prologue[] = { 0x56, 0x57, 0x8b, 0xf1, 0x33, 0xff };
    BYTE* movie;
    BYTE* destructor;
    DWORD protection;
    DWORD ignored;
    char mode[8];
    (void)module;
    (void)reserved;
    if (reason != 1) return 1;
    if ((DWORD)GetModuleHandleA(0) != 0x00400000) return 0;
    if (matches((BYTE*)0x00407080, base_prologue, sizeof(base_prologue)) &&
        matches((BYTE*)0x004d5770, destructor_prologue, sizeof(destructor_prologue)))
    {
        movie = (BYTE*)0x00407080;
        destructor = (BYTE*)0x004d5770;
    }
    else if (matches((BYTE*)0x00403be0, crossfire_prologue, sizeof(crossfire_prologue)) &&
             matches((BYTE*)0x004bf400, destructor_prologue, sizeof(destructor_prologue)))
    {
        movie = (BYTE*)0x00403be0;
        destructor = (BYTE*)0x004bf400;
    }
    else return 0;
    if (!matches(destructor, destructor_prologue, sizeof(destructor_prologue))) return 0;
    if (GetEnvironmentVariableA("SMAC_WINDOWED", mode, sizeof(mode)) == 1 && mode[0] == '1')
    {
        window_width = environment_number("SMAC_WINDOW_WIDTH", 1024);
        window_height = environment_number("SMAC_WINDOW_HEIGHT", 768);
        if (window_width < 800 || window_width > 3840 || window_width % 8 || window_height < 600 || window_height > 2160) return 0;
        BYTE* base = (BYTE*)GetModuleHandleA(0);
        if (!hook_import(base, "CreateWindowExA", create_window) ||
            !hook_import(base, "GetSystemMetrics", system_metrics) ||
            !hook_import(base, "GetCursorPos", cursor_position) ||
            !hook_import(base, "SetCursorPos", set_cursor_position) ||
            !hook_import(base, "SetWindowLongA", set_window_long)) return 0;
    }
    if (!VirtualProtect(movie, 5, 0x40, &protection)) return 0;
    movie[0] = 0xe9;
    *(DWORD*)(movie + 1) = (DWORD)show_movie - (DWORD)movie - 5;
    VirtualProtect(movie, 5, protection, &ignored);
    if (!VirtualProtect(destructor, 1, 0x40, &protection)) return 0;
    destructor[0] = 0xc3;
    VirtualProtect(destructor, 1, protection, &ignored);
    FlushInstructionCache(GetCurrentProcess(), 0, 0);
    return 1;
}

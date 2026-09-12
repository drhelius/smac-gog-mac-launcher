/* MIT License. Window/cursor API adaptation only; no game-code addresses or movie hooks. */
#include "win32_minimal.h"
#include "load_window.h"

static HWND game_window;
static WNDPROC game_proc;
static WCHAR helper_path[1024];
static int render_width = 1024;
static int render_height = 768;
static BOOL fullscreen;

static BOOL same_text(const char* left, const char* right)
{
    while (*left && *left == *right) { left++; right++; }
    return *left == *right;
}

static void hook_import(BYTE* base, const char* name, void* replacement)
{
    if (!base || *(unsigned short*)base != 0x5a4d) return;
    DWORD pe = *(DWORD*)(base + 60);
    if (pe > 1048576 || *(DWORD*)(base + pe) != 0x4550 || *(unsigned short*)(base + pe + 24) != 0x10b) return;
    DWORD size = *(DWORD*)(base + pe + 24 + 56);
    DWORD rva = *(DWORD*)(base + pe + 24 + 104);
    if (size < 4096 || !rva || rva >= size) return;
    for (unsigned int library = 0; library < 128 && rva <= size - 20; library++, rva += 20)
    {
        DWORD* descriptor = (DWORD*)(base + rva);
        if (!descriptor[3]) break;
        if (!descriptor[0] || descriptor[0] >= size || descriptor[4] >= size) continue;
        DWORD lookup = descriptor[0], address = descriptor[4];
        for (unsigned int index = 0; index < 4096 && lookup <= size - 4 && address <= size - 4; index++, lookup += 4, address += 4)
        {
            DWORD entry = *(DWORD*)(base + lookup);
            if (!entry) break;
            if ((entry & 0x80000000u) || entry >= size - 2) continue;
            const char* imported = (const char*)(base + entry + 2);
            unsigned int length = 0;
            while (entry + 2 + length < size && length < 128 && imported[length]) length++;
            if (length == 128 || entry + 2 + length >= size || !same_text(imported, name)) continue;
            DWORD protection, ignored;
            if (VirtualProtect(base + address, 4, 0x04, &protection))
            {
                *(DWORD*)(base + address) = (DWORD)replacement;
                VirtualProtect(base + address, 4, protection, &ignored);
            }
            return;
        }
    }
}

static DWORD window_style(DWORD style)
{
    style &= ~(0x00c00000u | 0x00040000u | 0x00010000u | 0x01000000u);
    return fullscreen ? style | 0x80000000u : (style & ~0x80000000u) | 0x00c00000u | 0x00080000u | 0x00020000u;
}

static void outer_size(DWORD style, DWORD extended, int* width, int* height)
{
    RECT rectangle = { 0, 0, render_width, render_height };
    if (fullscreen)
    {
        *width = GetSystemMetrics(0);
        *height = GetSystemMetrics(1);
    }
    else
    {
        AdjustWindowRectEx(&rectangle, style, 0, extended);
        *width = rectangle.right - rectangle.left;
        *height = rectangle.bottom - rectangle.top;
    }
}

static LONG WINAPI window_proc(HWND window, unsigned int message, DWORD wparam, LONG lparam)
{
    // The launcher owns presentation; do not let Alt+Enter switch the physical display.
    if (message == 0x0100 && wparam == 13 && GetAsyncKeyState(0x12) < 0) return 0;
    if (message == 0x007c && (LONG)wparam == -16 && lparam)
        ((DWORD*)lparam)[1] = window_style(((DWORD*)lparam)[1]);
    if ((message >= 0x0083 && message <= 0x0086) || message == 0x0112)
        return DefWindowProcA(window, message, wparam, lparam);
    return CallWindowProcA(game_proc, window, message, wparam, lparam);
}

static BOOL WINAPI cursor_position(POINT* point)
{
    if (!GetCursorPos(point)) return 0;
    if (!game_window) return 1;
    if (!ScreenToClient(game_window, point)) return 0;
    return point->x >= 0 && point->y >= 0 && point->x < render_width && point->y < render_height;
}

static BOOL WINAPI set_cursor(int x, int y)
{
    POINT point = { x, y };
    if (game_window) ClientToScreen(game_window, &point);
    return SetCursorPos(point.x, point.y);
}

static BOOL WINAPI clip_cursor(const RECT* rectangle)
{
    if (!rectangle || !game_window) return ClipCursor(rectangle);
    RECT screen = *rectangle;
    ClientToScreen(game_window, (POINT*)&screen.left);
    ClientToScreen(game_window, (POINT*)&screen.right);
    return ClipCursor(&screen);
}

static LONG WINAPI set_window_long(HWND window, int index, LONG value)
{
    if (window == game_window)
    {
        if (index == -16) value = (LONG)window_style((DWORD)value);
        if (index == -20 && !fullscreen) value &= ~0x8;
        if (index == -4)
        {
            LONG previous = (LONG)game_proc;
            game_proc = (WNDPROC)value;
            return previous;
        }
    }
    return SetWindowLongA(window, index, value);
}

static BOOL WINAPI place_window(HWND window, const WINDOW_PLACEMENT* placement)
{
    if (window != game_window) return SetWindowPlacement(window, placement);
    WINDOW_PLACEMENT adjusted = *placement;
    RECT current;
    int width, height;
    if (!GetWindowRect(window, &current)) return 0;
    outer_size((DWORD)GetWindowLongA(window, -16), (DWORD)GetWindowLongA(window, -20), &width, &height);
    adjusted.normal.left = fullscreen ? 0 : current.left;
    adjusted.normal.top = fullscreen ? 0 : current.top;
    adjusted.normal.right = adjusted.normal.left + width;
    adjusted.normal.bottom = adjusted.normal.top + height;
    return SetWindowPlacement(window, &adjusted);
}

static BOOL WINAPI position_window(HWND window, HWND after, int x, int y, int width, int height, unsigned int flags)
{
    if (window == game_window)
    {
        if (!(flags & 1)) outer_size((DWORD)GetWindowLongA(window, -16), (DWORD)GetWindowLongA(window, -20), &width, &height);
        if (fullscreen) { x = 0; y = 0; }
        else if (!(flags & 2) && x == 0 && y == 0)
        {
            RECT current;
            if (GetWindowRect(window, &current)) { x = current.left; y = current.top; }
        }
        if (!fullscreen && after == (HWND)-1) after = (HWND)-2;
    }
    return SetWindowPos(window, after, x, y, width, height, flags);
}

static LONG WINAPI display_mode(void* mode, DWORD flags) { (void)mode; (void)flags; return 0; }

static void install_window_calls(BYTE* module);

static HWND WINAPI create_window(DWORD extended, const char* class_name, const char* title, DWORD style,
                                int x, int y, int width, int height, HWND parent, HANDLE menu,
                                HMODULE instance, void* parameter)
{
    BOOL main = !game_window && !parent && width >= 640 && height >= 400;
    if (main)
    {
        // Thinker is loaded by its own launcher after our process-start hook.
        install_window_calls((BYTE*)GetModuleHandleA("thinker.dll"));
        style = window_style(style);
        if (!fullscreen) extended &= ~0x8u;
        outer_size(style, extended, &width, &height);
        x = fullscreen ? 0 : (GetSystemMetrics(0) - width) / 2;
        y = fullscreen ? 0 : (GetSystemMetrics(1) - height) / 2;
        if (!fullscreen && x < 20) x = 20;
        if (!fullscreen && y < 50) y = 50;
    }
    HWND result = CreateWindowExA(extended, class_name, title, style, x, y, width, height, parent, menu, instance, parameter);
    if (main && result)
    {
        game_window = result;
        game_proc = (WNDPROC)SetWindowLongA(result, -4, (LONG)window_proc);
        SetWindowPos(result, fullscreen ? (HWND)-1 : (HWND)-2, x, y, width, height, 0x0020 | 0x0010);
    }
    return result;
}

static void install_window_calls(BYTE* module)
{
    hook_import(module, "CreateWindowExA", create_window);
    hook_import(module, "GetCursorPos", cursor_position);
    hook_import(module, "SetCursorPos", set_cursor);
    hook_import(module, "ClipCursor", clip_cursor);
    hook_import(module, "SetWindowLongA", set_window_long);
    hook_import(module, "SetWindowPlacement", place_window);
    hook_import(module, "SetWindowPos", position_window);
    hook_import(module, "ChangeDisplaySettingsA", display_mode);
    hook_import(module, "ChangeDisplaySettingsW", display_mode);
}

static BOOL game_name(const char* app, const char* command)
{
    const char* name = app ? app : command;
    if (!name) return 0;
    BOOL quoted = *name == '"';
    if (quoted) name++;
    const char* base = name;
    for (const char* p = name; *p && (!quoted || *p != '"') && (app || quoted || *p != ' '); p++)
        if (*p == '\\' || *p == '/') base = p + 1;
    char filename[32];
    unsigned int i = 0;
    while (base[i] && base[i] != '"' && (app || quoted || base[i] != ' ') && i < sizeof(filename) - 1)
    {
        char c = base[i];
        filename[i++] = c >= 'A' && c <= 'Z' ? c + ('a' - 'A') : c;
    }
    filename[i] = 0;
    return same_text(filename, "terran.exe") || same_text(filename, "terranx.exe");
}

static BOOL WINAPI create_process(const char* app, char* command, void* process_security, void* thread_security,
                                  BOOL inherit, DWORD flags, void* environment, const char* directory,
                                  void* startup, PROCESS_INFO* process)
{
    if (!game_name(app, command)) return CreateProcessA(app, command, process_security, thread_security, inherit, flags, environment, directory, startup, process);
    if (!CreateProcessA(app, command, process_security, thread_security, inherit, flags | 4, environment, directory, startup, process)) return 0;
    if (!load_window_helper(process->process, helper_path))
    {
        TerminateProcess(process->process, 1114);
        CloseHandle(process->thread);
        CloseHandle(process->process);
        SetLastError(1114);
        return 0;
    }
    if (!(flags & 4)) ResumeThread(process->thread);
    return 1;
}

static int number(const char* name, int fallback)
{
    char value[16];
    DWORD length = GetEnvironmentVariableA(name, value, sizeof(value));
    if (!length || length >= sizeof(value)) return fallback;
    int result = 0;
    for (DWORD i = 0; i < length; i++)
    {
        if (value[i] < '0' || value[i] > '9') return fallback;
        result = result * 10 + value[i] - '0';
        if (result > 16384) return fallback;
    }
    return result;
}

BOOL WINAPI DllMain(HMODULE module, DWORD reason, void* reserved)
{
    (void)reserved;
    if (reason != 1) return 1;
    DWORD length = GetModuleFileNameW(module, helper_path, 1024);
    if (!length || length >= 1024) return 0;
    render_width = number("SMAC_WINDOW_WIDTH", 1024);
    render_height = number("SMAC_WINDOW_HEIGHT", 768);
    fullscreen = number("SMAC_FULLSCREEN", 0) != 0;
    install_window_calls((BYTE*)GetModuleHandleA(0));
    hook_import((BYTE*)GetModuleHandleA(0), "CreateProcessA", create_process);
    return 1;
}

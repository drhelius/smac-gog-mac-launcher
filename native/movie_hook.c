/* MIT License. In-memory movie redirection for the two hash-verified GOG executables.
 * Movie function locations were identified in PRACX and checked against our binaries.
 * No proprietary game instructions or assets are distributed in this file.
 */
#include "win32_minimal.h"

static const char request_path[] = "centauri-movie.request";
static const char done_path[] = "centauri-movie.done";

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

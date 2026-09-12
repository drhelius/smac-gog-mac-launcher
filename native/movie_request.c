/* MIT License. External movie command for PRACX/Thinker; no game patching or windows. */
#include "win32_minimal.h"

void __cdecl mainCRTStartup(void)
{
    WCHAR directory[1024];
    char name[128];
    DWORD length = GetModuleFileNameW(0, directory, 1024);
    if (!length || length >= 1024) ExitProcess(2);
    while (length && directory[length - 1] != '\\' && directory[length - 1] != '/') length--;
    if (!length) ExitProcess(2);
    directory[length - 1] = 0;
    if (!SetCurrentDirectoryW(directory)) ExitProcess(2);

    const WCHAR* command = GetCommandLineW();
    if (*command == '"')
    {
        command++;
        while (*command && *command != '"') command++;
        if (*command) command++;
    }
    else { while (*command && *command != ' ' && *command != '\t') command++; }
    while (*command == ' ' || *command == '\t') command++;
    if (*command == '"') command++;
    const WCHAR* base = command;
    for (const WCHAR* cursor = command; *cursor && *cursor != '"'; cursor++)
    {
        if (*cursor == '\\' || *cursor == '/') base = cursor + 1;
    }
    length = 0;
    while (*base && *base != '"' && length < sizeof(name) - 5)
    {
        WCHAR character = *base++;
        if (!((character >= 'a' && character <= 'z') || (character >= 'A' && character <= 'Z') ||
              (character >= '0' && character <= '9') || character == '_' || character == '-' ||
              character == '.' || character == ' ')) ExitProcess(2);
        name[length++] = (char)character;
    }
    while (length && name[length - 1] == ' ') length--;
    if (!length || length >= sizeof(name) - 5) ExitProcess(2);
    if (!(length > 4 && name[length - 4] == '.'))
    {
        name[length++] = '.';
        name[length++] = 'w';
        name[length++] = 'v';
        name[length++] = 'e';
    }
    DeleteFileA("centauri-movie.done");
    HANDLE file = CreateFileA("centauri-movie.tmp", 0x40000000, 0, 0, 2, 0x80, 0);
    if (file == INVALID_HANDLE_VALUE) ExitProcess(2);
    DWORD written;
    BOOL result = WriteFile(file, name, length, &written, 0);
    CloseHandle(file);
    if (!result || written != length || !MoveFileExA("centauri-movie.tmp", "centauri-movie.request", 0x1 | 0x8)) ExitProcess(2);
    DWORD start = GetTickCount();
    while (GetFileAttributesA("centauri-movie.done") == 0xffffffff && GetTickCount() - start < 900000) Sleep(50);
    result = DeleteFileA("centauri-movie.done");
    ExitProcess(result ? 0 : 2);
}

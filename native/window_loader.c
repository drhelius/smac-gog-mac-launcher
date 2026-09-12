/* MIT License. Run the selected mod launcher unchanged with our window API helper. */
#include "win32_minimal.h"
#include "load_window.h"

void __cdecl mainCRTStartup(void)
{
    WCHAR path[1024];
    DWORD length = GetModuleFileNameW(0, path, 1024);
    if (!length || length >= 1000) ExitProcess(2);
    while (length && path[length - 1] != '\\' && path[length - 1] != '/') length--;
    if (!length) ExitProcess(2);
    const char* name = "centauri_window.dll";
    while (*name) path[length++] = (WCHAR)*name++;
    path[length] = 0;

    WCHAR* command = GetCommandLineW();
    if (*command == '"')
    {
        command++;
        while (*command && *command != '"') command++;
        if (*command) command++;
    }
    else { while (*command && *command != ' ' && *command != '\t') command++; }
    while (*command == ' ' || *command == '\t') command++;
    if (!*command) ExitProcess(2);
    STARTUP_INFO startup = { 0 };
    PROCESS_INFO process = { 0 };
    startup.size = sizeof(startup);
    if (!CreateProcessW(0, command, 0, 0, 0, 4, 0, 0, &startup, &process)) ExitProcess(2);
    if (!load_window_helper(process.process, path))
    {
        TerminateProcess(process.process, 2);
        CloseHandle(process.thread);
        CloseHandle(process.process);
        ExitProcess(2);
    }
    ResumeThread(process.thread);
    CloseHandle(process.thread);
    WaitForSingleObject(process.process, 0xffffffff);
    DWORD result = 2;
    GetExitCodeProcess(process.process, &result);
    CloseHandle(process.process);
    ExitProcess(result);
}

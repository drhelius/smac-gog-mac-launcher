/* MIT License. Load our API-only window helper into a suspended x86 process. */
#ifndef SMAC_LOAD_WINDOW_H
#define SMAC_LOAD_WINDOW_H

static BOOL load_window_helper(HANDLE process, const WCHAR* path)
{
    DWORD length = 0, written = 0, result = 0;
    while (path[length] && length < 1023) length++;
    if (!length || length == 1023) return 0;
    DWORD size = (length + 1) * sizeof(WCHAR);
    void* remote = VirtualAllocEx(process, 0, size, 0x3000, 0x04);
    if (!remote) return 0;
    if (!WriteProcessMemory(process, remote, path, size, &written) || written != size)
    {
        VirtualFreeEx(process, remote, 0, 0x8000);
        return 0;
    }
    THREADPROC load = (THREADPROC)GetProcAddress(GetModuleHandleA("kernel32.dll"), "LoadLibraryW");
    HANDLE thread = load ? CreateRemoteThread(process, 0, 0, load, remote, 0, 0) : 0;
    DWORD wait = thread ? WaitForSingleObject(thread, 10000) : 0xffffffff;
    if (wait == 0) GetExitCodeThread(thread, &result);
    if (thread) CloseHandle(thread);
    // On timeout the caller terminates the child; do not free a live thread's argument.
    if (wait == 0 || !thread) VirtualFreeEx(process, remote, 0, 0x8000);
    return wait == 0 && result != 0;
}

#endif

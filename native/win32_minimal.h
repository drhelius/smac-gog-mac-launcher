/* Minimal Win32 ABI declarations for the freestanding x86 movie hook. MIT License. */
#ifndef CENTAURI_WIN32_MINIMAL_H
#define CENTAURI_WIN32_MINIMAL_H

#define WINAPI __stdcall
#define API __declspec(dllimport)
typedef unsigned char BYTE;
typedef unsigned long DWORD;
typedef int BOOL;
typedef void* HANDLE;
typedef void* HWND;
typedef void* HMODULE;
#define INVALID_HANDLE_VALUE ((HANDLE)-1)

API HANDLE WINAPI CreateFileA(const char*, DWORD, DWORD, void*, DWORD, DWORD, HANDLE);
API BOOL WINAPI WriteFile(HANDLE, const void*, DWORD, DWORD*, void*);
API BOOL WINAPI CloseHandle(HANDLE);
API BOOL WINAPI DeleteFileA(const char*);
API BOOL WINAPI MoveFileExA(const char*, const char*, DWORD);
API DWORD WINAPI GetFileAttributesA(const char*);
API DWORD WINAPI GetTickCount(void);
API void WINAPI Sleep(DWORD);
API HMODULE WINAPI GetModuleHandleA(const char*);
API BOOL WINAPI VirtualProtect(void*, DWORD, DWORD, DWORD*);
API BOOL WINAPI FlushInstructionCache(HANDLE, const void*, DWORD);
API HANDLE WINAPI GetCurrentProcess(void);
API HWND WINAPI GetActiveWindow(void);
API BOOL WINAPI ShowWindow(HWND, int);
API BOOL WINAPI SetForegroundWindow(HWND);
API BOOL WINAPI InvalidateRect(HWND, const void*, BOOL);

#endif

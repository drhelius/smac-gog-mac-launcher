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
typedef long LONG;
typedef struct { LONG x, y; } POINT;
typedef struct { LONG left, top, right, bottom; } RECT;
typedef LONG (WINAPI *WNDPROC)(HWND, unsigned int, DWORD, LONG);
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
API DWORD WINAPI GetEnvironmentVariableA(const char*, char*, DWORD);
API HWND WINAPI CreateWindowExA(DWORD, const char*, const char*, DWORD, int, int, int, int, HWND, HANDLE, HMODULE, void*);
API int WINAPI GetSystemMetrics(int);
API BOOL WINAPI GetCursorPos(POINT*);
API BOOL WINAPI SetCursorPos(int, int);
API BOOL WINAPI ScreenToClient(HWND, POINT*);
API BOOL WINAPI ClientToScreen(HWND, POINT*);
API BOOL WINAPI AdjustWindowRectEx(RECT*, DWORD, BOOL, DWORD);
API LONG WINAPI GetWindowLongA(HWND, int);
API LONG WINAPI SetWindowLongA(HWND, int, LONG);
API BOOL WINAPI SetWindowPos(HWND, HWND, int, int, int, int, unsigned int);
API LONG WINAPI DefWindowProcA(HWND, unsigned int, DWORD, LONG);
API LONG WINAPI CallWindowProcA(WNDPROC, HWND, unsigned int, DWORD, LONG);

#endif

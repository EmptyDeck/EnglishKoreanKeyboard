#include <windows.h>
#include <imm.h>
#include <stdio.h>

#pragma comment(lib, "imm32.lib")

bool isKoreanInputMode()
{
    // Get the handle of the current foreground window
    HWND hWnd = GetForegroundWindow();
    if (!hWnd)
    {
        return false; // No foreground window, assume English
    }

    // Get the keyboard layout for the thread of the foreground window
    HKL hKL = GetKeyboardLayout(GetWindowThreadProcessId(hWnd, NULL));
    if (LOWORD(hKL) != 0x0412)
    {
        return false; // Not Korean keyboard layout, assume English
    }

    // Get the default IME window associated with the foreground window
    HWND hIME = ImmGetDefaultIMEWnd(hWnd);
    if (!hIME)
    {
        return false; // No IME window, assume English
    }

    // Send message to get the IME conversion mode (IMC_GETCONVERSIONMODE = 0x0001)
    LRESULT conversionMode = SendMessage(hIME, WM_IME_CONTROL, 0x0001, 0);

    // Check if IME_CMODE_NATIVE (0x0001) is set, indicating Korean mode
    return (conversionMode & 0x0001) != 0;
}

int main()
{
    if (isKoreanInputMode())
    {
        printf("Korean input mode\n");
    }
    else
    {
        printf("English input mode\n");
    }
    return 0;
}
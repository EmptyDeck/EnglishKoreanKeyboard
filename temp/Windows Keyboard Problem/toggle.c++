#include <Windows.h>
#include <imm.h>
#include <iostream>

#pragma comment(lib, "imm32.lib")

int main() {
    // Get the handle to the current foreground window.
    HWND hWnd = GetForegroundWindow();
    if (!hWnd) {
        std::cerr << "Unable to get the foreground window." << std::endl;
        return 1;
    }

    // Retrieve the input context for the window.
    HIMC hIMC = ImmGetContext(hWnd);
    if (!hIMC) {
        std::cerr << "Unable to get the input context." << std::endl;
        return 1;
    }

    DWORD conversion = 0, sentence = 0;
    if (!ImmGetConversionStatus(hIMC, &conversion, &sentence)) {
        std::cerr << "Failed to get conversion status." << std::endl;
        ImmReleaseContext(hWnd, hIMC);
        return 1;
    }

    // Check the conversion mode flag.
    // The flag IME_CMODE_HANGUL is set when Hangul (Korean) mode is active.
    if (conversion & IME_CMODE_HANGUL) {
        std::cout << "Korean input mode (Hangul) is active." << std::endl;
    } else {
        std::cout << "English input mode is active." << std::endl;
    }

    // Always release the input context after using it.
    ImmReleaseContext(hWnd, hIMC);
    return 0;
}

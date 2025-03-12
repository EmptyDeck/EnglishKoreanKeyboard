import sys
import os
import platform
import subprocess
import time
import ctypes
from ctypes import wintypes
import torch
import torch.nn as nn
import numpy as np
from pynput import keyboard
from pynput.keyboard import Key, Controller
from PyQt6.QtWidgets import QApplication, QSystemTrayIcon, QMenu, QDialog, QVBoxLayout, QHBoxLayout, QCheckBox, QSpinBox, QSlider, QComboBox, QPushButton, QLabel
from PyQt6.QtGui import QIcon
from PyQt6.QtCore import QSettings, Qt
from process.KoEnMapper import conv_en2ko, conv_ko2en


# OS Detection (from your code)
IS_MAC = sys.platform == 'darwin'
IS_WIN = sys.platform.startswith('win')
IS_LINUX = sys.platform.startswith('linux')

# Your existing LanguageClassifier and related functions
ALPHABET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
SPECIALSIMBOLS = "1234567890!@#$%^&*()_+-=[]{}|;:,.<>?"

char_to_idx = {char: idx for idx, char in enumerate(ALPHABET)}


def one_hot_encode(letter):
    vec = np.zeros(len(ALPHABET), dtype=np.float32)
    if letter in char_to_idx:
        vec[char_to_idx[letter]] = 1.0
    return vec


class LanguageClassifier(nn.Module):
    def __init__(self, input_size=52, hidden_size=128, num_layers=1):
        super(LanguageClassifier, self).__init__()
        self.lstm = nn.LSTM(input_size, hidden_size,
                            num_layers, batch_first=True)
        self.fc = nn.Linear(hidden_size, 1)
        self.sigmoid = nn.Sigmoid()

    def forward(self, x, lengths):
        packed = nn.utils.rnn.pack_padded_sequence(
            x, lengths, batch_first=True, enforce_sorted=False)
        packed_out, (h_n, _) = self.lstm(packed)
        h_last = h_n[-1]
        out = self.fc(h_last)
        out = self.sigmoid(out)
        return out


model = LanguageClassifier(input_size=52, hidden_size=128, num_layers=1)
try:
    state_dict = torch.load("AI/best_model.pt")
    model.load_state_dict(state_dict, strict=False)
    print("Model loaded successfully.")
except FileNotFoundError:
    print("Model file not found.")
except Exception as e:
    print(f"Error loading model: {e}")


def predict_language(input_str):
    model.eval()
    seq = [one_hot_encode(ch) for ch in input_str if ch in char_to_idx]
    if not seq:
        return 0.5
    seq_tensor = torch.tensor(seq).unsqueeze(0)
    length = torch.tensor([len(seq)])
    with torch.no_grad():
        output = model(seq_tensor, length)
    return output.item()


# Your language switching functions
if IS_MAC:
    def switch_language(method=0):
        if method == 0:  # Control+Space
            command = """
            osascript -e 'tell application "System Events"
                key down control
                key down space
                key up space
                key up control
            end tell'
            """
            subprocess.run(command, shell=True)
        elif method == 1:  # Caps Lock
            kb = Controller()
            kb.press(Key.caps_lock)
            kb.release(Key.caps_lock)
        elif method == 2:  # Command+Space
            kb = Controller()
            kb.press(Key.cmd)
            kb.press(' ')
            kb.release(' ')
            kb.release(Key.cmd)

    def check_language_mode():
        # MacOS의 현재 입력 소스 확인
        command = "defaults read ~/Library/Preferences/com.apple.HIToolbox.plist AppleSelectedInputSources"
        result = subprocess.run(command, shell=True,
                                capture_output=True, text=True)
        input_source_data = result.stdout
        # English (ABC) 레이아웃 체크
        if '"KeyboardLayout Name" = ABC' in input_source_data or 'KeyboardLayout Name = ABC' in input_source_data:
            return 'en'
        # Korean 레이아웃 체크
        elif '"Bundle ID" = "com.apple.inputmethod.Korean"' in input_source_data or 'Bundle ID = com.apple.inputmethod.Korean' in input_source_data:
            return 'ko'
        else:
            return 'unknown'

elif IS_WIN:

    exe_path = "CheckCurrentLanguage.exe"
    # ULONG_PTR 타입 정의
    wintypes.ULONG_PTR = wintypes.WPARAM

    # User32.dll 로드
    hllDll = ctypes.WinDLL("User32.dll", use_last_error=True)

    # 한/영 키 Virtual Key 코드 (VK_HANGUEL)
    VK_HANGUEL = 0x15

    # INPUT 구조체 정의
    class MOUSEINPUT(ctypes.Structure):
        _fields_ = (("dx",          wintypes.LONG),
                    ("dy",          wintypes.LONG),
                    ("mouseData",   wintypes.DWORD),
                    ("dwFlags",     wintypes.DWORD),
                    ("time",        wintypes.DWORD),
                    ("dwExtraInfo", wintypes.ULONG_PTR))

    class HARDWAREINPUT(ctypes.Structure):
        _fields_ = (("uMsg",    wintypes.DWORD),
                    ("wParamL", wintypes.WORD),
                    ("wParamH", wintypes.WORD))

    class KEYBDINPUT(ctypes.Structure):
        _fields_ = (("wVk",         wintypes.WORD),  # Virtual-key code
                    ("wScan",       wintypes.WORD),  # Hardware scan code
                    ("dwFlags",     wintypes.DWORD),  # 플래그
                    ("time",        wintypes.DWORD),  # 시간
                    ("dwExtraInfo", wintypes.ULONG_PTR))  # 추가 정보

    class INPUT(ctypes.Structure):
        class _INPUT(ctypes.Union):
            _fields_ = (("ki", KEYBDINPUT),
                        ("mi", MOUSEINPUT),
                        ("hi", HARDWAREINPUT))
        _anonymous_ = ("_input",)  # 익명 유니온
        _fields_ = (("type",   wintypes.DWORD),  # 입력 타입
                    ("_input", _INPUT))       # 유니온 구조체

    def switch_language(method=0):
        kb = Controller()
        if method == 0:  # Hangul Key
            x = INPUT(type=1, ki=KEYBDINPUT(wVk=VK_HANGUEL))
            y = INPUT(type=1, ki=KEYBDINPUT(wVk=VK_HANGUEL, dwFlags=2))
            hllDll.SendInput(1, ctypes.byref(x), ctypes.sizeof(x))
            time.sleep(0.05)
            hllDll.SendInput(1, ctypes.byref(y), ctypes.sizeof(y))
        elif method == 1:  # Alt+Shift
            kb.press(Key.alt)
            kb.press(Key.shift)
            kb.release(Key.shift)
            kb.release(Key.alt)
        elif method == 2:  # Windows+Space
            kb.press(Key.cmd)
            kb.press(' ')
            kb.release(' ')
            kb.release(Key.cmd)

    def check_language_mode():
        """
        Executes the CheckCurrentLanguage.exe and returns the language code.

        Args:
            exe_path: The full path to the CheckCurrentLanguage.exe file.

        Returns:
            "ko" for Korean, "en" for English, "unknown" for others, or None if an error occurred.
        """
        try:
            if not os.path.exists(exe_path):
                return "Error, files does not exsist"

            result = subprocess.run(
                [exe_path], capture_output=True, text=True, check=True)
            output = result.stdout.strip()

            if "Korean input mode" in output:
                return "ko"
            elif "English (US) keyboard layout detected" in output:
                return "en"
            elif "Detected language: ko" in output:
                return "ko"
            elif "Detected language: en" in output:
                return "en"
            elif "Detected language:" in output:
                return "unknown"
            elif "No foreground window detected" in output:
                return "en"
            elif "Korean keyboard layout detected, but no IME window found." in output:
                return "en"
            elif "Korean keyboard layout detected, but Korean IME mode is inactive." in output:
                return "en"
            else:
                return "unknown"

        except (subprocess.CalledProcessError, FileNotFoundError, Exception):
            return None

elif IS_LINUX:
    def switch_language(method=0):
        current = 'us'  # Simplified; integrate with your check_language_mode if needed
        new_layout = 'kr' if current == 'us' else 'us'
        subprocess.run(f"setxkbmap {new_layout}", shell=True)

    def check_language_mode():
        """
        Checks the current keyboard layout and returns 'ko', 'en', or 'unknown'.
        """
        try:
            result = subprocess.run(
                ["setxkbmap", "-query"], capture_output=True, text=True)
            output = result.stdout
            layout_line = next(
                (line for line in output.splitlines() if "layout:" in line), None)

            if layout_line:
                layout = layout_line.split(":")[1].strip()
                if layout == "us":
                    return "en"
                elif layout == "kr":
                    return "ko"
                else:
                    return "unknown"
            else:
                return "unknown"

        except FileNotFoundError:
            return "unknown"  # setxkbmap not found
        except Exception as e:
            print(f"Error checking language mode: {e}")
            return "unknown"

# Settings Dialog


class SettingsDialog(QDialog):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Settings")
        self.settings = QSettings("MyCompany", "AutoHangulEnglish")
        self.initUI()
        self.loadSettings()

    def initUI(self):
        layout = QVBoxLayout()

        self.processOnSpaceCB = QCheckBox("Process on Space")
        layout.addWidget(self.processOnSpaceCB)

        self.bufferLengthLabel = QLabel("Buffer Length Threshold:")
        self.bufferLengthSpin = QSpinBox()
        self.bufferLengthSpin.setRange(1, 50)
        layout.addWidget(self.bufferLengthLabel)
        layout.addWidget(self.bufferLengthSpin)

        # Confidence threshold with number display
        self.confidenceLabel = QLabel("Confidence Threshold:")
        self.confidenceSlider = QSlider(Qt.Orientation.Horizontal)
        self.confidenceSlider.setRange(50, 100)  # 0.5 to 1.0
        self.confidenceSlider.setTickInterval(1)
        self.confidenceSlider.setTickPosition(QSlider.TickPosition.TicksBelow)
        self.confidenceValueLabel = QLabel("0.99 (99%)")  # Initial value
        self.confidenceSlider.valueChanged.connect(self.updateConfidenceLabel)

        layout.addWidget(self.confidenceLabel)
        layout.addWidget(self.confidenceSlider)
        layout.addWidget(self.confidenceValueLabel)

        # Language toggle with descriptive names
        self.toggleMethodLabel = QLabel("Language Toggle Method:")
        self.toggleMethodCombo = QComboBox()
        self.toggleMethodCombo.addItems(
            ["Keyboard Shortcut", "Mouse Click", "Auto Detect"])
        layout.addWidget(self.toggleMethodLabel)
        layout.addWidget(self.toggleMethodCombo)

        self.resetButton = QPushButton("Reset to Default")
        self.resetButton.clicked.connect(self.resetToDefault)
        layout.addWidget(self.resetButton)

        self.tipLabel = QLabel("💡 Press 1+2+3 simultaneously to pause")
        layout.addWidget(self.tipLabel)

        buttonLayout = QHBoxLayout()
        okButton = QPushButton("OK")
        okButton.clicked.connect(self.accept)
        cancelButton = QPushButton("Cancel")
        cancelButton.clicked.connect(self.reject)
        buttonLayout.addWidget(okButton)
        buttonLayout.addWidget(cancelButton)
        layout.addLayout(buttonLayout)

        self.setLayout(layout)

    def updateConfidenceLabel(self, value):
        confidence = value / 100.0
        self.confidenceValueLabel.setText(f"{confidence:.2f} ({value}%)")

    def loadSettings(self):
        print("Loading settings...")
        self.processOnSpaceCB.setChecked(
            self.settings.value("processOnSpace", False, type=bool))
        self.bufferLengthSpin.setValue(self.settings.value(
            "bufferLengthThreshold", 10, type=int))
        confidence = self.settings.value(
            "confidenceThreshold", 0.99, type=float)
        slider_value = int(confidence * 100)
        self.confidenceSlider.setValue(slider_value)
        self.updateConfidenceLabel(slider_value)
        self.toggleMethodCombo.setCurrentIndex(
            self.settings.value("languageToggleMethod", 0, type=int))
        print("Settings loaded")

    def saveSettings(self):
        print("Saving settings...")
        self.settings.setValue(
            "processOnSpace", self.processOnSpaceCB.isChecked())
        self.settings.setValue("bufferLengthThreshold",
                               self.bufferLengthSpin.value())
        confidence = self.confidenceSlider.value() / 100.0
        self.settings.setValue("confidenceThreshold", confidence)
        self.settings.setValue("languageToggleMethod",
                               self.toggleMethodCombo.currentIndex())
        print("Settings saved")

    def resetToDefault(self):
        print("Resetting to default...")
        self.processOnSpaceCB.setChecked(False)
        self.bufferLengthSpin.setValue(10)
        self.confidenceSlider.setValue(99)
        self.toggleMethodCombo.setCurrentIndex(0)
        self.updateConfidenceLabel(99)

    def accept(self):
        print("Accept clicked")
        self.saveSettings()
        print("Calling super().accept()")
        super().accept()
        print("Accept completed")

    def reject(self):
        print("Cancel clicked")
        super().reject()
# Main Application
# Main Application


class MainApp:
    def __init__(self):
        self.app = QApplication(sys.argv)
        self.settings = QSettings("SJ", "AutoHangulEnglish")
        self.isPaused = False
        self.pressed_keys = set()
        self.buffered_word = ""
        self.physical_keyboard = Controller()
        self.listener = None  # Initialize listener as None
        self.setupTrayIcon()
        self.setupKeyMonitoring()
        # Connect aboutToQuit signal for cleanup
        self.app.aboutToQuit.connect(self.cleanup)

    def setupTrayIcon(self):
        self.trayIcon = QSystemTrayIcon()
        # Determine base directory: use __file__ if available, otherwise cwd
        if '__file__' in globals():
            base_dir = os.path.dirname(os.path.abspath(__file__))
        else:
            base_dir = os.getcwd()  # Fallback to current working directory
        active_icon_path = os.path.join(base_dir, "active_icon.png")
        self.trayIcon.setIcon(QIcon(active_icon_path))  # Use absolute path
        self.trayIcon.setToolTip("AutoHangulEnglish")

        self.trayMenu = QMenu()
        self.pauseAction = self.trayMenu.addAction("Pause")
        self.pauseAction.triggered.connect(self.togglePause)
        self.settingsAction = self.trayMenu.addAction("Settings")
        self.settingsAction.triggered.connect(self.openSettings)
        self.quitAction = self.trayMenu.addAction("Quit")
        # Connect to custom quit method
        self.quitAction.triggered.connect(self.quitApp)

        self.trayIcon.setContextMenu(self.trayMenu)
        self.trayIcon.show()

    def togglePause(self):
        self.isPaused = not self.isPaused
        # Determine base directory: use __file__ if available, otherwise cwd
        if '__file__' in globals():
            base_dir = os.path.dirname(os.path.abspath(__file__))
        else:
            base_dir = os.getcwd()  # Fallback to current working directory
        if self.isPaused:
            self.pauseAction.setText("Resume")
            self.trayIcon.setIcon(
                QIcon(os.path.join(base_dir, "paused_icon.png")))
            if self.listener and self.listener.is_alive():
                self.listener.stop()
            # Simulate backspaces to remove '1', '2', '3'
            for _ in range(3):
                self.physical_keyboard.press(Key.backspace)
                self.physical_keyboard.release(Key.backspace)
        else:
            self.pauseAction.setText("Pause")
            self.trayIcon.setIcon(
                QIcon(os.path.join(base_dir, "active_icon.png")))
            self.listener = keyboard.Listener(
                on_press=self.on_press, on_release=self.on_release)
            self.listener.start()

    def openSettings(self):
        dialog = SettingsDialog()
        dialog.exec()

    def setupKeyMonitoring(self):
        self.listener = keyboard.Listener(
            on_press=self.on_press, on_release=self.on_release)
        if not self.isPaused:
            self.listener.start()
#

    def on_press(self, key):
        try:
            # Ignore shift keys so characters like '?' can be added without resetting the buffer
            if key in (Key.shift, Key.shift_r, Key.shift_l):
                return
            # Handle space key separately
            if key == Key.space:
                self.buffered_word += " "
                self.process_buffer()
                return

            if hasattr(key, 'char') and key.char is not None:
                char = conv_ko2en(key.char)
                print("converted char:", char)

                if char in '123':
                    self.pressed_keys.add(char)
                    if {'1', '2', '3'}.issubset(self.pressed_keys):
                        self.togglePause()
                if self.isPaused:
                    return
                if char in ALPHABET or char in SPECIALSIMBOLS:
                    self.buffered_word += char
                    self.process_buffer()
                else:
                    self.buffered_word = ""
            else:
                self.buffered_word = ""
        except:
            self.buffered_word = ""

    def on_release(self, key):
        try:
            if hasattr(key, 'char'):  # Only process character keys
                char = key.char
                if char in '123':
                    self.pressed_keys.discard(char)
        except:
            pass

    def process_buffer(self):
        print(f"Buffered word: {self.buffered_word}")
        process_on_space = self.settings.value(
            "processOnSpace", False, type=bool)
        buffer_length = self.settings.value(
            "bufferLengthThreshold", 10, type=int)
        confidence_threshold = self.settings.value(
            "confidenceThreshold", 0.99, type=float)

        if (process_on_space and ' ' in self.buffered_word) or len(self.buffered_word) >= buffer_length and self.buffered_word[-1] == ' ':

            prob = predict_language(self.buffered_word)
            print(
                f"Buffered word: {self.buffered_word}, Probability: {prob: .4f}")
            if prob >= confidence_threshold:
                target_lang = 'en'
            elif prob <= (1 - confidence_threshold):
                target_lang = 'ko'
            else:
                self.buffered_word = ""
                return

            current_lang = check_language_mode()
            if current_lang != target_lang:
                method = self.settings.value(
                    "languageToggleMethod", 0, type=int)
                switch_language(method)

                if current_lang == 'ko':  # this is so that the buffered word is converted to the correct language to delete
                    self.buffered_word = conv_en2ko(self.buffered_word)

                    self.physical_keyboard.press(Key.left)
                    self.physical_keyboard.release(Key.left)
                    self.physical_keyboard.press(Key.right)
                    self.physical_keyboard.release(Key.right)
                for _ in range(len(self.buffered_word)):
                    self.physical_keyboard.press(Key.backspace)
                    self.physical_keyboard.release(Key.backspace)

                if target_lang == 'ko':
                    self.physical_keyboard.type(conv_en2ko(self.buffered_word))
                elif target_lang == 'en':
                    self.physical_keyboard.type(conv_ko2en(self.buffered_word))

            self.buffered_word = ""

    def quitApp(self):
        """Custom method to cleanly quit the application."""
        if self.listener and self.listener.is_alive():
            self.listener.stop()
        self.trayIcon.hide()
        self.app.quit()
        sys.exit(0)

    def cleanup(self):
        """Cleanup method called when the application is about to quit."""
        if self.listener and self.listener.is_alive():
            self.listener.stop()

    def run(self):
        sys.exit(self.app.exec())


if __name__ == "__main__":
    app = MainApp()
    app.run()
#

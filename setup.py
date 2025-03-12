from cx_Freeze import setup, Executable
import sys
import os

sys.setrecursionlimit(5000)

base = None
if sys.platform == "win32":
    base = "Win32GUI"

executables = [
    Executable(
        script="UI_Grok.py",
        base=base,
        target_name="AutoHangulEnglish",
        icon="active_icon.ico"
    )
]

packages = [
    "torch",
    "numpy",
    "pynput",
    "PyQt6",
    "process"
]

include_files = [
    ("AI/best_model.pt", "AI/best_model.pt"),
    ("active_icon.png", "active_icon.png"),
    ("paused_icon.png", "paused_icon.png"),
    ("CheckCurrentLanguage.exe", "CheckCurrentLanguage.exe"),
    ("process/KoEnMapper.py", "process/KoEnMapper.py"),
    ("/opt/homebrew/opt/libiodbc/lib/libiodbc.2.dylib", "lib/libiodbc.2.dylib")
]

setup(
    name="AutoHangulEnglish",
    version="1.0",
    description="Automatic Hangul-English Language Switcher",
    options={
        "build_exe": {
            "packages": packages,
            "include_files": include_files,
            # Exclude SQL module
            "excludes": ["coremltools", "tkinter", "PyQt6.QtSql"],
            "include_msvcr": True,
            "path": sys.path,
            "optimize": 2,
        }
    },
    executables=executables
)

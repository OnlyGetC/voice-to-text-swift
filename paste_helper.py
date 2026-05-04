#!/usr/bin/env python3
"""
paste_helper.py — вставляет текст из буфера обмена в активное поле.
Вызывается из VoiceToText.app после транскрибации.
"""
import sys
import time
import subprocess

def paste():
    # Способ 1: pynput (если установлен)
    try:
        from pynput.keyboard import Controller, Key
        kb = Controller()
        time.sleep(0.05)
        with kb.pressed(Key.cmd):
            kb.press('v')
            kb.release('v')
        return
    except ImportError:
        pass

    # Способ 2: osascript keystroke
    subprocess.run([
        'osascript', '-e',
        'tell application "System Events" to keystroke "v" using command down'
    ])

if __name__ == '__main__':
    paste()

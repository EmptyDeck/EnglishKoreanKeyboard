//
//  utils.swift
//  AutoHangulEnglish
//
//  Created by 김정우 on 2/28/25.
//

import Carbon

func isKoreanInputSource() -> Bool {
    guard let inputSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
        return false
    }
    
    guard let inputSourceID = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID) else {
        return false
    }
    
    let inputSourceIDString = Unmanaged<CFString>.fromOpaque(inputSourceID).takeUnretainedValue() as String
    return inputSourceIDString.lowercased().contains("korean") || inputSourceIDString.lowercased().contains("hangul")
}

func hangulToQwerty(_ input: String) -> String {
    let mapping: [Character: Character] = [
        "ㅂ": "q", "ㅈ": "w", "ㄷ": "e", "ㄱ": "r", "ㅅ": "t",
        "ㅛ": "y", "ㅕ": "u", "ㅑ": "i", "ㅐ": "o", "ㅔ": "p",
        "ㅁ": "a", "ㄴ": "s", "ㅇ": "d", "ㄹ": "f", "ㅎ": "g",
        "ㅗ": "h", "ㅓ": "j", "ㅏ": "k", "ㅣ": "l",
        "ㅋ": "z", "ㅌ": "x", "ㅊ": "c", "ㅍ": "v", "ㅠ": "b",
        "ㅜ": "n", "ㅡ": "m"
    ]
    
    var result = ""
    for char in input {
        result.append(mapping[char] ?? char)
    }
    return result
}

func qwertyToHangul(_ input: String) -> String {
    let mapping: [Character: Character] = [
        "q": "ㅂ", "w": "ㅈ", "e": "ㄷ", "r": "ㄱ", "t": "ㅅ",
        "y": "ㅛ", "u": "ㅕ", "i": "ㅑ", "o": "ㅐ", "p": "ㅔ",
        "a": "ㅁ", "s": "ㄴ", "d": "ㅇ", "f": "ㄹ", "g": "ㅎ",
        "h": "ㅗ", "j": "ㅓ", "k": "ㅏ", "l": "ㅣ",
        "z": "ㅋ", "x": "ㅌ", "c": "ㅊ", "v": "ㅍ", "b": "ㅠ",
        "n": "ㅜ", "m": "ㅡ"
    ]
    
    var result = ""
    for char in input {
        result.append(mapping[char] ?? char)
    }
    return result
}

// 한글 여부 판별 함수
func isHangul(_ char: String) -> Bool {
    return char.range(of: "\\p{Hangul}", options: .regularExpression) != nil
}

// 영어 여부 판별 함수
func isEnglish(_ char: String) -> Bool {
    return char.range(of: "[a-zA-Z]", options: .regularExpression) != nil
}

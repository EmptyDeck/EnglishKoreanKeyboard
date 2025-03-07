    //
    //  KoEnConv2.swift
    //  AutoHangulEnglish
    //
    //  Created by 김정우 on 3/2/25.
    //

    import Foundation

    //오토마타의 상태를 정의
    enum HangulStatus {
        case start //s0
        case chosung //s1
        case joongsung, dJoongsung //s2,s3
        case jongsung, dJongsung //s4, s5
        case endOne, endTwo //s6,s7
    }

    //입력된 키의 종류 판별 정의
    enum HangulCHKind {
        case consonant //자음
        case vowel  //모음
    }

    //키 입력마다 쌓이는 입력 스택 정의
    struct InpStack {
        var curhanst: HangulStatus //상태
        var key: UInt32 //방금 입력된 키 코드
        var charCode: String //조합된 코드
        var chKind: HangulCHKind // 입력된 키가 자음인지 모임인지
    }

    final class HangulAutomata {
        
        var buffer: [String] = []
        
        var inpStack: [InpStack] = []
        
        var currentHangulState: HangulStatus?
        
        private var chKind = HangulCHKind.vowel
        
        private var charCode: String = ""
        private var oldKey: UInt32 = 0
        private var oldChKind: HangulCHKind?
        private var keyCode: UInt32 = 0
        
        private var chosungTable: [String] = ["ㄱ","ㄲ", "ㄴ", "ㄷ", "ㄸ", "ㄹ", "ㅁ", "ㅂ", "ㅃ", "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅉ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"]
        
        private var joongsungTable: [String] = ["ㅏ", "ㅐ", "ㅑ", "ㅒ", "ㅓ", "ㅔ", "ㅕ", "ㅖ", "ㅗ", "ㅘ", "ㅙ", "ㅚ", "ㅛ", "ㅜ", "ㅝ", "ㅞ", "ㅟ", "ㅠ", "ㅡ", "ㅢ", "ㅣ"]
        
        private var jongsungTable: [String] = [" ", "ㄱ", "ㄲ", "ㄳ", "ㄴ", "ㄵ", "ㄶ", "ㄷ", "ㄹ", "ㄺ", "ㄻ", "ㄼ", "ㄽ", "ㄾ", "ㄿ","ㅀ", "ㅁ", "ㅂ", "ㅄ", "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"]
        
        private var dJoongTable: [[String]] = [
            ["ㅗ","ㅏ","ㅘ"],
            ["ㅗ","ㅐ","ㅙ"],
            ["ㅗ","ㅣ","ㅚ"],
            ["ㅜ","ㅓ","ㅝ"],
            ["ㅜ","ㅔ","ㅞ"],
            ["ㅜ","ㅣ","ㅟ"],
            ["ㅡ","ㅣ","ㅢ"],
            ["ㅏ","ㅣ","ㅐ"],
            ["ㅓ","ㅣ","ㅔ"],
            ["ㅕ","ㅣ","ㅖ"],
            ["ㅑ","ㅣ","ㅒ"],
            ["ㅘ","ㅣ","ㅙ"]
        ]
        
        private var dJongTable: [[String]] = [
            ["ㄱ","ㅅ","ㄳ"],
            ["ㄴ","ㅈ","ㄵ"],
            ["ㄴ","ㅎ","ㄶ"],
            ["ㄹ","ㄱ","ㄺ"],
            ["ㄹ","ㅁ","ㄻ"],
            ["ㄹ","ㅂ","ㄼ"],
            ["ㄹ","ㅅ","ㄽ"],
            ["ㄹ","ㅌ","ㄾ"],
            ["ㄹ","ㅍ","ㄿ"],
            ["ㄹ","ㅎ","ㅀ"],
            ["ㅂ","ㅅ","ㅄ"]
        ]
        
        private func joongsungPair() -> Bool {
            for i in 0..<dJoongTable.count {
                if dJoongTable[i][0] == joongsungTable[Int(oldKey)] && dJoongTable[i][1] == joongsungTable[Int(keyCode)] {
                    keyCode = UInt32(joongsungTable.firstIndex(of: dJoongTable[i][2]) ?? 0)
                    return true
                }
            }
            return false
        }
        
        private func jongsungPair() -> Bool {
            for i in 0..<dJongTable.count {
                if dJongTable[i][0] == jongsungTable[Int(oldKey)] && dJongTable[i][1] == chosungTable[Int(keyCode)] {
                    keyCode = UInt32(jongsungTable.firstIndex(of: dJongTable[i][2]) ?? 0)
                    return true
                }
            }
            return false
        }
        
        private func isJoongSungPair(first: String, result: String) -> Bool {
            for i in 0..<dJoongTable.count {
                if dJoongTable[i][0] == first && dJoongTable[i][2] == result {
                    return true
                }
            }
            return false
        }
        
        private func decompositionChosung(charCode: UInt32) -> UInt32 {
            let unicodeHangul = charCode - 0xAC00
            let jongsung = (unicodeHangul) % 28
            let joongsung = ((unicodeHangul - jongsung) / 28) % 21
            let chosung = (((unicodeHangul - jongsung) / 28) - joongsung) / 21
            return chosung
        }
        
        private func decompositionChosungJoongsung(charCode: UInt32) -> UInt32 {
            let unicodeHangul = charCode - 0xAC00
            let jongsung = (unicodeHangul) % 28
            let joongsung = ((unicodeHangul - jongsung) / 28) % 21
            let chosung = (((unicodeHangul - jongsung) / 28) - joongsung) / 21
            return combinationHangul(chosung: chosung, joongsung: joongsung, jongsung: keyCode)
        }
        
        private func combinationHangul(chosung: UInt32 = 0, joongsung: UInt32, jongsung: UInt32 = 0) -> UInt32 {
            return (((chosung * 21) + joongsung) * 28) + jongsung + 0xAC00
        }
        
        func deleteBuffer() {
            if inpStack.count == 0 {
                if buffer.count > 0 {
                    buffer.removeLast()
                }
            } else {
                if let popHanguel = inpStack.popLast() {
                    if popHanguel.curhanst == .chosung {
                        buffer.removeLast()
                    } else if popHanguel.curhanst == .joongsung || popHanguel.curhanst == .dJoongsung {
                        if inpStack[inpStack.count - 1].curhanst == .jongsung || inpStack[inpStack.count - 1].curhanst == .dJongsung {
                            buffer.removeLast()
                        }
                            buffer[buffer.count - 1] = inpStack[inpStack.count - 1].charCode
                    } else {
                        if inpStack.isEmpty {
                            buffer.removeLast()
                        } else if popHanguel.chKind == .vowel {
                            if inpStack[inpStack.count - 1].curhanst == .jongsung {
                                if inpStack[inpStack.count - 1].chKind == .vowel {
                                    if isJoongSungPair(first: joongsungTable[Int(inpStack[inpStack.count - 1].key)] , result: joongsungTable[Int(popHanguel.key)]) {
                                        buffer[buffer.count - 1] = inpStack[inpStack.count - 1].charCode
                                    } else {
                                        buffer.removeLast()
                                    }
                                }
                            } else {
                                buffer.removeLast()
                            }
                        } else {
                            buffer[buffer.count - 1] = inpStack[inpStack.count - 1].charCode
                        }
                    }
                    if inpStack.isEmpty {
                        currentHangulState = nil
                    } else {
                        currentHangulState = inpStack[inpStack.count - 1].curhanst
                        oldKey = inpStack[inpStack.count - 1].key
                        oldChKind = inpStack[inpStack.count - 1].chKind
                        charCode = inpStack[inpStack.count - 1].charCode
                    }
                }
            }
        }
    }

    extension HangulAutomata {
        func hangulAutomata(key: String) {
            
            var canBeJongsung: Bool = false
            
            if joongsungTable.contains(key) {
                chKind = .vowel
                keyCode = UInt32(joongsungTable.firstIndex(of: key) ?? 0)
            } else {
                chKind = .consonant
                keyCode = UInt32(chosungTable.firstIndex(of: key) ?? 0)
                if !((key == "ㄸ") || (key == "ㅉ") || (key == "ㅃ")) {
                    canBeJongsung = true
                }
            }
            if currentHangulState != nil {
                oldKey = inpStack[inpStack.count - 1].key
                oldChKind = inpStack[inpStack.count - 1].chKind
            } else {
                currentHangulState = .start
                buffer.append("")
            }
            
            //MARK: - 오토마타 전이 알고리즘
            switch currentHangulState {
            case .start:
                if chKind == .consonant {
                    currentHangulState = .chosung
                } else {
                    currentHangulState = .jongsung
                }
            case .chosung:
                if chKind == .vowel {
                    currentHangulState = .joongsung
                } else {
                    currentHangulState = .endOne
                }
            case .joongsung:
                if canBeJongsung {
                    currentHangulState = .jongsung
                } else if joongsungPair() {
                    currentHangulState = .dJoongsung
                } else {
                    currentHangulState = .endOne
                }
            case .dJoongsung:
                //추가
                if joongsungPair() {
                    currentHangulState = .dJoongsung
                } else if canBeJongsung {
                    currentHangulState = .jongsung
                } else {
                    currentHangulState = .endOne
                }
            case .jongsung:
                if (chKind == .consonant) && jongsungPair() {
                    currentHangulState = .dJongsung
                } else if chKind == .vowel {
                    currentHangulState = .endTwo
                } else {
                    currentHangulState = .endOne
                }
            case .dJongsung:
                if chKind == .vowel {
                    currentHangulState = .endTwo
                } else {
                    currentHangulState = .endOne
                }
            default:
                break
            }
            //MARK: - 오토마타 상태 별 작업 알고리즘
            
            switch currentHangulState {
            case .chosung:
                charCode = chosungTable[Int(keyCode)]
            case .joongsung:
                charCode = String(Unicode.Scalar(combinationHangul(chosung: oldKey, joongsung: keyCode)) ?? Unicode.Scalar(0))
            case .dJoongsung:
                let currentChosung = decompositionChosung(charCode: Unicode.Scalar(charCode)?.value ?? 0)
                charCode = String(Unicode.Scalar(combinationHangul(chosung: currentChosung, joongsung: keyCode)) ?? Unicode.Scalar(0))
            case .jongsung:
                if canBeJongsung {
                    keyCode = UInt32(jongsungTable.firstIndex(of: key) ?? 0)
                    let currentCharCode =  Unicode.Scalar(charCode)?.value ?? 0
                    charCode = String(Unicode.Scalar(decompositionChosungJoongsung(charCode: currentCharCode)) ?? Unicode.Scalar(0))
                } else {
                    charCode = key
                }
            case .dJongsung:
                let currentCharCode = Unicode.Scalar(charCode)?.value ?? 0
                charCode = String(Unicode.Scalar(decompositionChosungJoongsung(charCode: currentCharCode)) ?? Unicode.Scalar(0))
                keyCode = UInt32(jongsungTable.firstIndex(of: key) ?? 0)
            case .endOne:
                if chKind == .consonant {
                    charCode = chosungTable[Int(keyCode)]
                    currentHangulState = .chosung
                } else {
                    charCode = joongsungTable[Int(keyCode)]
                    currentHangulState = .jongsung
                }
                buffer.append("")
            case .endTwo:
                if oldChKind == .consonant {
                    oldKey = UInt32(chosungTable.firstIndex(of: jongsungTable[Int(oldKey)]) ?? 0)
                    charCode =  String(Unicode.Scalar(combinationHangul(chosung: oldKey, joongsung: keyCode)) ?? Unicode.Scalar(0))
                    currentHangulState = .joongsung
                    buffer[buffer.count - 1] = inpStack[inpStack.count - 2].charCode
                    buffer.append("")
                } else {
                    if !joongsungPair() {
                        buffer.append("")
                    }
                    charCode = joongsungTable[Int(keyCode)]
                    currentHangulState = nil
                    currentHangulState = .jongsung
                }
            default:
                break
            }
            inpStack.append(InpStack(curhanst: currentHangulState ?? .start, key: keyCode, charCode: String(Unicode.Scalar(charCode) ?? Unicode.Scalar(0)), chKind: chKind))
    //        print("charCode:", charCode, " / buffer: ", buffer)
            buffer[buffer.count - 1] = charCode
        }
    }

    // 한글 유니코드 완전 분해 (초성, 중성, 종성 기본 자모로 분리)
    func decomposeHangul(_ char: Character) -> [String] {
        let scalar = char.unicodeScalars.first!.value
        
        // 한글 영역이 아닌 경우
        guard scalar >= 0xAC00 && scalar <= 0xD7A3 else {
            return [String(char)]
        }
        
        let base = Int(scalar) - 0xAC00
        let initialIndex = base / (21 * 28)
        let medialIndex = (base % (21 * 28)) / 28
        let finalIndex = base % 28
        
        // 초성, 중성, 종성 기본 자모
        let initialJamo = [
            "ㄱ", "ㄲ", "ㄴ", "ㄷ", "ㄸ", "ㄹ", "ㅁ",
            "ㅂ", "ㅃ", "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅉ",
            "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"
        ][initialIndex]
        
        let medialJamo = [
            "ㅏ", "ㅐ", "ㅑ", "ㅒ", "ㅓ", "ㅔ", "ㅕ",
            "ㅖ", "ㅗ", "ㅘ", "ㅙ", "ㅚ", "ㅛ", "ㅜ",
            "ㅝ", "ㅞ", "ㅟ", "ㅠ", "ㅡ", "ㅢ", "ㅣ"
        ][medialIndex]
        
        let finalJamo = [
            "", "ㄱ", "ㄲ", "ㄳ", "ㄴ", "ㄵ", "ㄶ",
            "ㄷ", "ㄹ", "ㄺ", "ㄻ", "ㄼ", "ㄽ", "ㄾ",
            "ㄿ", "ㅀ", "ㅁ", "ㅂ", "ㅄ", "ㅅ", "ㅆ",
            "ㅇ", "ㅈ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"
        ][finalIndex]
        
        // 복합 자모 분해 규칙
        let decomposeRules: [String: [String]] = [
            "ㄲ": ["ㄱ", "ㄱ"],
            "ㄳ": ["ㄱ", "ㅅ"],
            "ㄵ": ["ㄴ", "ㅈ"],
            "ㄶ": ["ㄴ", "ㅎ"],
            "ㄺ": ["ㄹ", "ㄱ"],
            "ㄻ": ["ㄹ", "ㅁ"],
            "ㄼ": ["ㄹ", "ㅂ"],
            "ㄽ": ["ㄹ", "ㅅ"],
            "ㄾ": ["ㄹ", "ㅌ"],
            "ㄿ": ["ㄹ", "ㅍ"],
            "ㅀ": ["ㄹ", "ㅎ"],
            "ㅄ": ["ㅂ", "ㅅ"],
            "ㅘ": ["ㅗ", "ㅏ"],
            "ㅙ": ["ㅗ", "ㅐ"],
            "ㅚ": ["ㅗ", "ㅣ"],
            "ㅝ": ["ㅜ", "ㅓ"],
            "ㅞ": ["ㅜ", "ㅔ"],
            "ㅟ": ["ㅜ", "ㅣ"],
            "ㅢ": ["ㅡ", "ㅣ"],
            "ㅆ": ["ㅅ", "ㅅ"]
        ]
        
        // 분해 수행
        func splitJamo(_ jamo: String) -> [String] {
            return decomposeRules[jamo] ?? [jamo]
        }
        
        let initialSplit = splitJamo(initialJamo)
        let medialSplit = splitJamo(medialJamo)
        let finalSplit = splitJamo(finalJamo)
        
        return initialSplit + medialSplit + finalSplit
    }

    // 2-벌식 키보드 매핑 (물리적 키 위치 기반)
    let qwertyKeyMap: [String: String] = [
        // 초성
        "ㄱ": "r", "ㄲ": "R", "ㄴ": "s", "ㄷ": "e", "ㄸ": "E",
        "ㄹ": "f", "ㅁ": "a", "ㅂ": "q", "ㅃ": "Q", "ㅅ": "t",
        "ㅆ": "T", "ㅇ": "d", "ㅈ": "w", "ㅉ": "W", "ㅊ": "c",
        "ㅋ": "z", "ㅌ": "x", "ㅍ": "v", "ㅎ": "g",
        
        // 중성
        "ㅏ": "k", "ㅐ": "o", "ㅑ": "i", "ㅒ": "O",
        "ㅓ": "j", "ㅔ": "p", "ㅕ": "u", "ㅖ": "P",
        "ㅗ": "h", "ㅛ": "y", "ㅜ": "n", "ㅠ": "b",
        "ㅡ": "m", "ㅣ": "l",
        
        // 종성 (초성과 다른 경우)
        "ㄳ": "rt", "ㄵ": "sw", "ㄶ": "sg",
        "ㄺ": "fr", "ㄻ": "fa", "ㄼ": "fq",
        "ㄽ": "ft", "ㄾ": "fx", "ㄿ": "fv",
        "ㅀ": "fg", "ㅄ": "qt"
    ]

    // 최종 변환 함수
    func convertKo2EN(_ input: String) -> String {
        return input.reduce("") { result, char in
            let decomposed = decomposeHangul(char)
                .compactMap { qwertyKeyMap[$0] ?? $0 }
                .joined()
                .lowercased()
            
            return result + decomposed
        }
    }

// MARK: HOW TO USE

//
//let hangulAutomata = HangulAutomata()
////소ㅑㄴ ㅑㄴ 두히ㅑ노
//
//let input = "ㅅㅗㅑㄴ  ㅑㄴ ㄷㅜㅎㅣㅑㄴㅗ"
//
//for char in input {
//    hangulAutomata.hangulAutomata(key: String(char))
//}
//
//print(hangulAutomata.buffer.joined()) // "한글" 출력








// MARK: CONVEN2KO


// Starting at Unicode hex 12593
let rawMapper = ["r", "R", "rt", "s", "sw", "sg", "e", "E", "f", "fr", "fa", "fq", "ft", "fx", "fv", "fg", "a", "q",
                "Q", "qt", "t", "T", "d", "w", "W", "c", "z", "x", "v", "g", "k", "o", "i", "O", "j", "p", "u", "P",
                "h", "hk", "ho", "hl", "y", "n", "nj", "np", "nl", "b", "m", "ml", "l"]

let koTopEn = ["r", "R", "s", "e", "E", "f", "a", "q", "Q", "t", "T", "d", "w", "W", "c", "z", "x", "v", "g"]
let koMidEn = ["k", "o", "i", "O", "j", "p", "u", "P", "h", "hk", "ho", "hl", "y", "n", "nj", "np", "nl", "b", "m",
               "ml", "l"]
let koBotEn = ["", "r", "R", "rt", "s", "sw", "sg", "e", "f", "fr", "fa", "fq", "ft", "fx", "fv", "fg", "a", "q",
               "qt", "t", "T", "d", "w", "c", "z", "x", "v", "g"]
               
let enLowerOnly = ["A", "B", "C", "D", "F", "G", "H", "I", "J", "K", "L", "M", "N", "S", "U", "V", "X", "Y", "Z"]

let T: Int = 0xB_0001_0000
let M: Int = 0xB_0000_0100
let B: Int = 0xB_0000_0001
let TM = T + M
let TMM = T + M + M
let TMB = T + M + B
let TMMB = T + M + M + B
let TMBB = T + M + B + B
let TMMBB = T + M + M + B + B

let combLen: [Int: Int] = [
    T: 1,
    M: 1,
    B: 1,
    TM: 2,
    TMM: 3,
    TMB: 3,
    TMMB: 4,
    TMBB: 4,
    TMMBB: 5,
]

/**
 Check the attach-ability for those two parameters.
 
 - Parameters:
   - i: The former character
   - l: The latter character
 
 - Returns:
   - 1: First Consonant + First Consonant (Not used)
   - 2: First Consonant + Vowel
   - 3: Vowel + Vowel
   - 4: Vowel + Final Consonant
   - 5: Final Consonant + Final Consonant
 */
func isAttachAvailable(_ i: String, _ l: String) -> Int {
    // First consonant + Vowel
    if koTopEn.contains(i) && koMidEn.contains(l) {
        return 2
    }
    // Vowel + Vowel
    if koMidEn.contains(i + l) {
        return 3
    }
    // Vowel + Final consonant
    if koMidEn.contains(i) && koBotEn.contains(l) {
        return 4
    }
    // Final consonant + Final consonant
    if koBotEn.contains(i + l) {
        return 5
    }
    return 0
}

/**
 Split English words based on Korean.
 
 - Parameter string: Input string to split
 
 - Returns: Array of groups that have a set of Korean parts
 */
func splitEn(_ string: String) -> [Any] {
    // Process string to lowercase
    var processedString = ""
    for char in string {
        let charString = String(char)
        if enLowerOnly.contains(charString) {
            processedString.append(charString.lowercased())
        } else {
            processedString.append(char)
        }
    }
    
    var jump = 0
    var separated: [Any] = []
    
    let characters = Array(processedString)
    
    for (index, char) in characters.enumerated() {
        var shift = 0
        var combination = T
        var currentIdx: Int? = nil
        
        if jump > 0 {
            jump -= 1
            continue
        } else if char == " " || char.isNumber || !char.isLetter {
            separated.append(String(char))
            continue
        } else {
            currentIdx = index
            
            // Check bounds for all potential access
            if currentIdx! + shift + 1 < characters.count {
                let currentChar = String(characters[currentIdx! + shift])
                let nextChar = String(characters[currentIdx! + shift + 1])
                
                if isAttachAvailable(currentChar, nextChar) == 2 { // 자 + 모
                    shift += 1
                    combination += M
                    
                    if currentIdx! + shift + 1 < characters.count {
                        let currentChar2 = String(characters[currentIdx! + shift])
                        let nextChar2 = String(characters[currentIdx! + shift + 1])
                        
                        if isAttachAvailable(currentChar2, nextChar2) == 3 { // 모 + 모
                            shift += 1
                            combination += M
                        }
                        
                        if currentIdx! + shift + 1 < characters.count {
                            let currentChar3 = String(characters[currentIdx! + shift])
                            let nextChar3 = String(characters[currentIdx! + shift + 1])
                            
                            if isAttachAvailable(currentChar3, nextChar3) == 4 { // 모 + 자
                                shift += 1
                                combination += B
                                
                                if currentIdx! + shift + 1 < characters.count {
                                    let currentChar4 = String(characters[currentIdx! + shift])
                                    let nextChar4 = String(characters[currentIdx! + shift + 1])
                                    
                                    let attachment3 = isAttachAvailable(currentChar4, nextChar4)
                                    
                                    if attachment3 == 5 { // 자 + 자 (종) + ?
                                        if currentIdx! + shift + 2 == characters.count { // IndexOutOfRange
                                            combination += B
                                        } else {
                                            shift += 1
                                            let currentChar5 = String(characters[currentIdx! + shift])
                                            let nextChar5 = String(characters[currentIdx! + shift + 1])
                                            
                                            let attachment4 = isAttachAvailable(currentChar5, nextChar5)
                                            
                                            if attachment4 == 2 { // 자 + 자 + 모
                                                // Do nothing
                                            } else { // 자 + 자 + 자 (다음)
                                                combination += B
                                            }
                                        }
                                    } else if attachment3 == 2 { // 자 + 모 (다음)
                                        combination -= B // Remove 'b'
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        if combination == T {
            separated.append(String(characters[currentIdx!]))
        } else if combination == TM {
            separated.append([String(characters[currentIdx!]), String(characters[currentIdx! + 1])])
        } else if combination == TMM {
            separated.append([String(characters[currentIdx!]), String(characters[currentIdx! + 1]) + String(characters[currentIdx! + 2])])
        } else if combination == TMB {
            separated.append([String(characters[currentIdx!]), String(characters[currentIdx! + 1]), String(characters[currentIdx! + 2])])
        } else if combination == TMMB {
            separated.append([String(characters[currentIdx!]), String(characters[currentIdx! + 1]) + String(characters[currentIdx! + 2]), String(characters[currentIdx! + 3])])
        } else if combination == TMBB {
            separated.append([String(characters[currentIdx!]), String(characters[currentIdx! + 1]), String(characters[currentIdx! + 2]) + String(characters[currentIdx! + 3])])
        } else if combination == TMMBB {
            separated.append([String(characters[currentIdx!]), String(characters[currentIdx! + 1]) + String(characters[currentIdx! + 2]), String(characters[currentIdx! + 3]) + String(characters[currentIdx! + 4])])
        }
        
        jump = (combLen[combination] ?? 1) - 1
    }
    
    return separated
}

/**
 Convert English characters to Korean characters.
 
 - Parameter string: Input string to convert
 
 - Returns: Converted Korean string
 */
func convEn2Ko(_ string: String) -> String {
    let charGroups = splitEn(string)
    var convertedString = ""
    
    for charGroup in charGroups {
        var topIdx = 0
        var midIdx = 0
        var botIdx = 0
        
        if let charGroupString = charGroup as? String {
            if charGroupString == " " || charGroupString.first?.isNumber == true || !(charGroupString.first?.isLetter ?? false) {
                convertedString += charGroupString
                continue
            }
            
            if let index = rawMapper.firstIndex(of: charGroupString) {
                convertedString += String(UnicodeScalar(index + 12593)!)
            }
        } else if let charGroupArray = charGroup as? [String] {
            for (index, part) in charGroupArray.enumerated() {
                if index == 0 {
                    topIdx = koTopEn.firstIndex(of: part) ?? 0
                } else if index == 1 {
                    midIdx = koMidEn.firstIndex(of: part) ?? 0
                } else if index == 2 {
                    botIdx = koBotEn.firstIndex(of: part) ?? 0
                }
            }
            
            let unicodeValue = (topIdx * 21 * 28 + midIdx * 28 + botIdx) + 44032
            convertedString += String(UnicodeScalar(unicodeValue)!)
        }
    }
    
    return convertedString
}


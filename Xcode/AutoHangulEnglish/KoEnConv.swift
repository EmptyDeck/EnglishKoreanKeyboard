import Foundation

extension Character {

    func unicodeScalarCodePoint() -> UInt32 {
        let unicodeScalars = self.unicodeScalars

        return unicodeScalars[unicodeScalars.startIndex].value
    }

}

class KeyboardAutomata {
    
    // MARK: - Hangeul status

    enum Status {
        case start
        case choSung
        case doubleChosung
        case jungSung
        case combinedJungsung
        case jongSung
        case combinedJongsung
        case end
    }

    // MARK: - Properties

    var outputToDisplay = String()
    private var inputContents = String() {
        willSet {
            guard let lastChar = newValue.last else { return }
            var newInput = lastChar
            
            if isEnglish(String(newInput)) {
                let convertedString = qwertyToHangul(String(newInput))
                if let convertedChar = convertedString.first {
                    newInput = convertedChar
                }
            }
            else {
                
            }
            
            changeToOutput(from: newInput)
        }
    }
    private var status: Status = .start {
        didSet {
            if status == .end {
                status = .start
            }
        }
    }
    private var isSpaceTyped = false

    // MARK: - Combining hangeul methods

    private func changeToOutput(from input: Character) {
        if outputToDisplay == Text.empty {
            allocateStatus(to: input)
            completeOutputString(from: input)
        } else {
            let lastCharacter = outputToDisplay.removeLast()
            allocateStatus(to: input, compare: lastCharacter)
            completeOutputString(from: input, with: lastCharacter)
        }
    }

    private func allocateStatus(to input: Character, compare lastCharacter: Character? = nil) {
        if let lastCharacter = lastCharacter {
            status = modify(status: status, with: input, compare: lastCharacter)
            return
        }
        status = modify(status: status, with: input)
    }

    private func completeOutputString(from input: Character, with lastCharacter: Character? = nil) {
        let string = combine(input, with: lastCharacter, for: status)
        outputToDisplay.append(string)
    }

    private func combine(
        _ character: Character,
        with last : Character? = nil,
        for status: Status
    ) -> String {
        var next = String(character)
        
        switch status {
        case .start:
            if last != nil {
                next = String(last!) + String(character)
            }

        case .choSung:
            if last != nil {
                next = String(last!) + String(character)
            }

        case .doubleChosung:
            guard let index = choSungList.firstIndex(of: character) else {
                return next
            }
            next = String(choSungList[index + 1])

        case .jungSung:
            guard let last = last else {
                return next
            }
            if jungSungList.contains(last) {
                next = String(last) + String(next)
                return next
            }
            if choSungList.contains(last) {
                next = compose(choSung: last, jungSung: character, jongSung: nil)
                return next
            }
            var decomposed = decompose(char: last)
            let jongsung = decomposed.removeLast()
            let jungsung = decomposed.removeLast()
            let chosung = decomposed.removeLast()
            if choSungList.contains(jongsung) {
                next = compose(choSung: chosung, jungSung: jungsung, jongSung: nil) + compose(choSung: jongsung, jungSung: character, jongSung: nil)
            } else {
                var combinedJongsungCharacter = decompose(combinedJongsung: jongsung)
                let secondCombinedCharacter = combinedJongsungCharacter.removeLast()
                let firstCombinedCharacter = combinedJongsungCharacter.removeLast()
                next = compose(choSung: chosung, jungSung: jungsung, jongSung: firstCombinedCharacter) + compose(choSung: secondCombinedCharacter, jungSung: character, jongSung: nil)
            }

        case .combinedJungsung:
            var decomposed = decompose(char: last!)
            _ = decomposed.removeLast()
            let lastJungsung = decomposed.removeLast()
            let jungsung = String([lastJungsung, character])
            let chosung = decomposed.removeLast()
            let combinedJungsung = combinedJungSungList[jungsung]!
            return compose(choSung: chosung, jungSung: combinedJungsung, jongSung: nil)

        case .jongSung:
            if last == Text.space {
                next = String(Text.space) + next
                return next
            }
            var decomposed = decompose(char: last!)
            _ = decomposed.removeLast()
            let jungsung = decomposed.removeLast()
            let chosung = decomposed.removeLast()
            next = compose(choSung: chosung, jungSung: jungsung, jongSung: character)

        case .combinedJongsung:
            var decomposed = decompose(char: last!)
            let jongsung = decomposed.removeLast()
            let jungsung = decomposed.removeLast()
            let chosung = decomposed.removeLast()
            let combinedJongsungCharacter = String([jongsung, character])
            if let combinedJongsung = combinedJongSungList[combinedJongsungCharacter] {
                next = compose(choSung: chosung, jungSung: jungsung, jongSung: combinedJongsung)
            }

        case .end:
            break
        }
        
        return next
    }

    private func modify(status: Status, with char: Character, compare last : Character? = nil) -> Status {
        switch status {
        case .start:
            if jungSungList.contains(char) {
                if last != nil {
                    return Status.jungSung
                }
                return Status.end
            } else if last == char {
                return Status.doubleChosung
            } else {
                return Status.choSung
            }

        case .choSung:
            if jungSungList.contains(char) {
                return Status.jungSung
            } else if let last = last,
                      char == last,
                      doubleChoSungList.keys.contains(char) {
                return Status.doubleChosung
            } else {
                return Status.end
            }

        case .doubleChosung:
            if jungSungList.contains(char) {
                return Status.jungSung
            }
            return Status.end

        case .jungSung:
            if jungSungList.contains(last!) {
                return Status.choSung
            } else if jongSungList.contains(char) {
                return Status.jongSung
            } else if let last = last {
                if jungSungList.contains(last) {
                    return Status.jungSung
                }
                var decomposed = decompose(char: last)
                decomposed.removeLast()
                let lastJungsung = decomposed.last
                if isCanBeCombinedJungSung(with: "\(lastJungsung!)\(char)") {
                    return Status.combinedJungsung
                }
                return Status.end
            } else {
                return Status.end
            }

        case .combinedJungsung:
            if jongSungList.contains(char) {
                return Status.jongSung
            } else if let last = last {
                var decomposed = decompose(char: last)
                _ = decomposed.removeLast()
                let lastJungsung = decomposed.removeLast()
                if isCanBeCombinedJungSung(with: "\(lastJungsung)\(char)") {
                    return Status.combinedJungsung
                }
                return Status.end
            } else {
                return Status.end
            }

        case .jongSung:
            if last == Text.space {
                return Status.choSung
            }
            if jungSungList.contains(char) {
                return Status.jungSung
            }

            var decomposed = decompose(char: last!)
            let jongsung = decomposed.removeLast()
            if combinedJongsungPossibleList.contains(jongsung) {
                let combinedJongsungCharacter = String(jongsung) + String(char)
                if let _ = combinedJongSungList[combinedJongsungCharacter] {
                    return Status.combinedJongsung
                }
            }
            
            if jongSungList.contains(char) {
                return Status.end
            }

            if jungSungList.contains(char) {
                return Status.jungSung
            } else if combinedJongsungPossibleList.contains(jongsung) {
                let combinedJongsungCharacter = String(jongsung) + String(char)
                if let _ = combinedJongSungList[combinedJongsungCharacter] {
                    return Status.combinedJongsung
                }
                if jongsung == char {
                    return Status.choSung
                }
                return Status.choSung
            } else {
                return Status.end
            }

        case .combinedJongsung:
            if jungSungList.contains(char) {
                return Status.jungSung
            }
            return Status.end

        case .end:
            return Status.start
        }
    }
    
    // MARK: - Keyboard function methods
    
    func insert(_ input: String) {
        isSpaceTyped = false
        inputContents.append(input)
    }

    func reset() {
        inputContents.removeAll()
    }
    
    func delete() {
        var currentString = outputToDisplay

        if isSpaceTyped {
            _ = outputToDisplay.popLast()
            status = .start
            return
        }

        if outputToDisplay != Text.empty {
            let lastCharacter = currentString.removeLast()
            if choSungList.contains(lastCharacter) ||
                jungSungList.contains(lastCharacter) ||
                lastCharacter == Text.space {
                outputToDisplay.removeLast()
                status = .start
            } else {
                var decomposed = decompose(char: lastCharacter)
                let jongsung = decomposed.removeLast()
                let jungsung = decomposed.removeLast()
                let chosung = decomposed.removeLast()
                if jongsung == Text.space {
                    outputToDisplay.removeLast()
                    outputToDisplay.append(chosung)
                    status = .choSung
                } else if isCombinedJongsung(with: jongsung) {
                    var combinedJongsungCharacters = decompose(combinedJongsung: jongsung)
                    _ = combinedJongsungCharacters.removeLast()
                    let firstJongsung = combinedJongsungCharacters.removeLast()
                    let string = compose(choSung: chosung, jungSung: jungsung, jongSung: firstJongsung)
                    outputToDisplay.removeLast()
                    outputToDisplay.append(string)
                    status = .jongSung
                } else {
                    outputToDisplay.removeLast()
                    let string = compose(choSung: chosung, jungSung: jungsung, jongSung: nil)
                    outputToDisplay.append(string)
                    status = .jungSung
                }
            }
        }
    }
    
    func space() {
        isSpaceTyped = true
        outputToDisplay.append(Text.space)
    }
    
    // MARK: - Combined hangeul related methods
    
    private func isCanBeCombinedJungSung(with vowels: String) -> Bool {
        return combinedJungSungList.keys.contains(vowels)
    }

    private func isCombinedJongsung(with jongsung: Character) -> Bool {
        if let _ = combinedJongSungList.values.firstIndex(of: jongsung) {
            return true
        }
        return false
    }
    
    private func decompose(combinedJongsung: Character) -> String {
        if let index = combinedJongSungList.values.firstIndex(of: combinedJongsung) {
            let combinedJongsungCharacter = combinedJongSungList[index].key
            return combinedJongsungCharacter
        }
        return String(combinedJongsung)
    }

    // MARK: - Calculating unicode methods
    
    private let baseUnicodeValue = 0xAC00
    
    private func compose(choSung: Character, jungSung: Character, jongSung: Character?) -> String {
        var choSungIndex = 0
        var jungSungIndex = 0
        var jongSungIndex = 0
        
        for i in 0..<choSungList.count {
            if choSungList[i] == choSung { choSungIndex = i }
        }

        for i in 0..<jungSungList.count {
            if jungSungList[i] == jungSung { jungSungIndex = i }
        }

        if let jongSung = jongSung {
            for i in 0..<jongSungList.count {
                if jongSungList[i] == jongSung { jongSungIndex = i }
            }
        }

        let calculatedValue: Int = (choSungIndex * jungSungList.count * jongSungList.count)
        + (jungSungIndex * jongSungList.count)
        + (jongSungIndex)
        + baseUnicodeValue
        
        if let unicode = Unicode.Scalar(calculatedValue) {
            let character = Character(unicode)
            return String(character)
        }

        return Text.empty
    }
    
    private func decompose(char: Character) -> String {
        let unicode = char.unicodeScalarCodePoint()
        
        // 1. 한글 음절 (가-힣)인 경우: 기존 로직 적용
        if (0xAC00...0xD7AF).contains(unicode) {
            // 기존 decomposition 로직
            let base = unicode - 0xAC00
            let jong = base % 28
            let jung = (base / 28) % 21
            let cho = (base / 28 / 21)
            return "\(choSungList[Int(cho)])\(jungSungList[Int(jung)])\(jongSungList[Int(jong)])"
        }
        // 2. 초성 자모 (ᄀ-ᄒ)인 경우: 초성으로 직접 매핑
        else if (0x1100...0x1112).contains(unicode) {
            let index = Int(unicode - 0x1100)
            return index < choSungList.count ? String(choSungList[index]) : String(char)
        }
        // 3. 중성 자모 (ᅡ-ᅵ)인 경우: 중성으로 직접 매핑
        else if (0x1161...0x1175).contains(unicode) {
            let index = Int(unicode - 0x1161)
            return index < jungSungList.count ? String(jungSungList[index]) : String(char)
        }
        // 4. 종성 자모 (ᆨ-ᇂ)인 경우: 종성으로 직접 매핑
        else if (0x11A8...0x11C2).contains(unicode) {
            let index = Int(unicode - 0x11A8)
            return index < jongSungList.count ? String(jongSungList[index]) : String(char)
        }
        // 5. 기타 문자: 그대로 반환
        else {
            return String(char)
        }
    }
    // MARK: - Hangeul Charact List

    private let choSungList: [Character] = ["ㄱ","ㄲ","ㄴ","ㄷ","ㄸ","ㄹ","ㅁ","ㅂ","ㅃ","ㅅ","ㅆ","ㅇ","ㅈ","ㅉ","ㅊ","ㅋ","ㅌ","ㅍ","ㅎ"]

    private let jungSungList: [Character] = ["ㅏ", "ㅐ", "ㅑ", "ㅒ", "ㅓ", "ㅔ", "ㅕ", "ㅖ", "ㅗ", "ㅘ", "ㅙ", "ㅚ", "ㅛ", "ㅜ", "ㅝ","ㅞ", "ㅟ", "ㅠ", "ㅡ", "ㅢ", "ㅣ"]

    private let jongSungList: [Character] = [" ", "ㄱ", "ㄲ", "ㄳ", "ㄴ", "ㄵ", "ㄶ", "ㄷ", "ㄹ", "ㄺ", "ㄻ", "ㄼ", "ㄽ", "ㄾ", "ㄿ","ㅀ", "ㅁ", "ㅂ", "ㅄ", "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"]

    private let combinedJongsungPossibleList: [Character] = ["ㄱ", "ㄴ", "ㄹ", "ㅂ"]

    private let combinedJungSungList: [String : Character] = [
        "ㅗㅏ" : "ㅘ",
        "ㅗㅐ" : "ㅙ",
        "ㅗㅣ" : "ㅚ",
        "ㅜㅓ" : "ㅝ",
        "ㅜㅔ" : "ㅞ",
        "ㅜㅣ" : "ㅟ",
        "ㅡㅣ" : "ㅢ",
        "ㅓㅣ" : "ㅔ",
        "ㅏㅣ" : "ㅐ",
        "ㅕㅣ" : "ㅖ",
        "ㅑㅣ" : "ㅒ",
        "ㅘㅣ" : "ㅙ",
        "ㅝㅣ" : "ㅞ"
    ]
    
    private let doubleChoSungList: [Character: Character] = [
        "ㄱ": "ㄲ",
        "ㄷ": "ㄸ",
        "ㅂ": "ㅃ",
        "ㅅ": "ㅆ",
        "ㅈ": "ㅉ"
    ]
    
    private let combinedJongSungList: [String : Character] = [
        "ㄱㅅ" : "ㄳ",
        "ㄴㅈ" : "ㄵ",
        "ㄴㅎ" : "ㄶ",
        "ㄹㄱ" : "ㄺ",
        "ㄹㅁ" : "ㄻ",
        "ㄹㅂ" : "ㄼ",
        "ㄹㅅ" : "ㄽ",
        "ㄹㅌ" : "ㄾ",
        "ㄹㅍ" : "ㄿ",
        "ㄹㅎ" : "ㅀ",
        "ㅂㅅ" : "ㅄ"
    ]

}

// MARK: - NameSpaces

extension KeyboardAutomata {
    
    private enum Text {
        static let empty: String = ""
        static let space: Character = " "
    }

}

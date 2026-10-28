import Foundation

public enum TypingMethod: String, CaseIterable, Identifiable {
    case telex = "Telex"
    case vni = "VNI"
    case simpleTelex = "Simple Telex"
    
    public var id: String { rawValue }
}

public enum ToneMarkType: Int {
    case none = 0
    case acute = 1    // Sắc
    case grave = 2    // Huyền
    case hook = 3     // Hỏi
    case tilde = 4    // Ngã
    case dot = 5      // Nặng
}

public class VietnameseEngine {
    public static let shared = VietnameseEngine()
    
    // Bản đồ nguyên âm và các biến thể dấu
    // Nguyên âm gốc: a, ă, â, e, ê, i, o, ô, ơ, u, ư, y
    private let toneMap: [Character: [ToneMarkType: Character]] = [
        "a": [.acute: "á", .grave: "à", .hook: "ả", .tilde: "ã", .dot: "ạ"],
        "A": [.acute: "Á", .grave: "À", .hook: "Ả", .tilde: "Ã", .dot: "Ạ"],
        "ă": [.acute: "ắ", .grave: "ằ", .hook: "ẳ", .tilde: "ẵ", .dot: "ặ"],
        "Ă": [.acute: "Ắ", .grave: "Ằ", .hook: "Ẳ", .tilde: "Ẵ", .dot: "Ặ"],
        "â": [.acute: "ấ", .grave: "ầ", .hook: "ẩ", .tilde: "ẫ", .dot: "ậ"],
        "Â": [.acute: "Ấ", .grave: "Ầ", .hook: "Ẩ", .tilde: "Ẫ", .dot: "Ậ"],
        "e": [.acute: "é", .grave: "è", .hook: "ẻ", .tilde: "ẽ", .dot: "ẹ"],
        "E": [.acute: "É", .grave: "È", .hook: "Ẻ", .tilde: "Ẽ", .dot: "Ẹ"],
        "ê": [.acute: "ế", .grave: "ề", .hook: "ể", .tilde: "ễ", .dot: "ệ"],
        "Ê": [.acute: "Ế", .grave: "Ề", .hook: "Ể", .tilde: "Ễ", .dot: "Ệ"],
        "i": [.acute: "í", .grave: "ì", .hook: "ỉ", .tilde: "ĩ", .dot: "ị"],
        "I": [.acute: "Í", .grave: "Ì", .hook: "Ỉ", .tilde: "Ĩ", .dot: "Ị"],
        "o": [.acute: "ó", .grave: "ò", .hook: "ỏ", .tilde: "õ", .dot: "ọ"],
        "O": [.acute: "Ó", .grave: "Ò", .hook: "Ỏ", .tilde: "Õ", .dot: "Ọ"],
        "ô": [.acute: "ố", .grave: "ồ", .hook: "ổ", .tilde: "ỗ", .dot: "ộ"],
        "Ô": [.acute: "Ố", .grave: "Ồ", .hook: "Ổ", .tilde: "Ỗ", .dot: "Ộ"],
        "ơ": [.acute: "ớ", .grave: "ờ", .hook: "ở", .tilde: "ỡ", .dot: "ợ"],
        "Ơ": [.acute: "Ớ", .grave: "Ờ", .hook: "Ở", .tilde: "Ỡ", .dot: "Ợ"],
        "u": [.acute: "ú", .grave: "ù", .hook: "ủ", .tilde: "ũ", .dot: "ụ"],
        "U": [.acute: "Ú", .grave: "Ù", .hook: "Ủ", .tilde: "Ũ", .dot: "Ụ"],
        "ư": [.acute: "ứ", .grave: "ừ", .hook: "ử", .tilde: "ữ", .dot: "ự"],
        "Ư": [.acute: "Ứ", .grave: "Ừ", .hook: "Ử", .tilde: "Ữ", .dot: "Ự"],
        "y": [.acute: "ý", .grave: "ỳ", .hook: "ỷ", .tilde: "ỹ", .dot: "ỵ"],
        "Y": [.acute: "Ý", .grave: "Ỳ", .hook: "Ỷ", .tilde: "Ỹ", .dot: "Ỵ"]
    ]
    
    // Bảng chuẩn hoá nguyên âm có dấu về dạng nguyên âm gốc + dấu
    private var reverseToneMap: [Character: (base: Character, tone: ToneMarkType)] = [:]
    
    private init() {
        for (base, tones) in toneMap {
            for (tone, charWithTone) in tones {
                reverseToneMap[charWithTone] = (base, tone)
            }
        }
    }
    
    /// Xử lý biến đổi từ tiếng Việt
    public func processWord(currentWord: String, newChar: Character, method: TypingMethod, modernOrthography: Bool = true) -> (transformed: String, didTransform: Bool) {
        guard let ascii = newChar.asciiValue, (ascii >= 65 && ascii <= 90) || (ascii >= 97 && ascii <= 122) || (ascii >= 48 && ascii <= 57) else {
            return (currentWord + String(newChar), false)
        }
        // "process", "class", "string": no Vietnamese syllable starts with
        // pr/cl/str, so leave the keys alone instead of adding and removing
        // marks mid-word. Every avoided replacement is one less burst of
        // synthetic keys an app can drop while typing fast.
        guard hasVietnameseOnset(currentWord) else {
            return (currentWord + String(newChar), false)
        }

        switch method {
        case .telex, .simpleTelex:
            return processTelex(currentWord: currentWord, newChar: newChar, modern: modernOrthography)
        case .vni:
            return processVNI(currentWord: currentWord, newChar: newChar, modern: modernOrthography)
        }
    }
    
    private func processTelex(currentWord: String, newChar: Character, modern: Bool) -> (String, Bool) {
        let lower = Character(newChar.lowercased())
        let isUpper = newChar.isUppercase
        
        // 1. Phím mũ và biến đổi nguyên âm/phụ âm: aa->â, ee->ê, oo->ô, dd->đ, w->ư/ơ/ă
        if !currentWord.isEmpty {
            let lastChar = currentWord.last!
            let lastLower = Character(lastChar.lowercased())
            let lastIsUpper = lastChar.isUppercase

            // Repeating a Telex transformation key cancels the conversion and
            // leaves the key literal: ass -> as, aaa -> aa, ddd -> dd.
            if lower == "d" && lastLower == "đ" {
                var word = currentWord
                word.removeLast()
                word.append(lastIsUpper ? "D" : "d")
                word.append(newChar)
                return (word, true)
            }
            if lower == "a" && lastLower == "â" {
                return replacingLast(in: currentWord, with: lastIsUpper ? "A" : "a", appending: newChar)
            }
            if lower == "e" && lastLower == "ê" {
                return replacingLast(in: currentWord, with: lastIsUpper ? "E" : "e", appending: newChar)
            }
            if lower == "o" && lastLower == "ô" {
                return replacingLast(in: currentWord, with: lastIsUpper ? "O" : "o", appending: newChar)
            }
            if lower == "w", let horned = hornedUOPair(in: currentWord), horned.isHorned {
                var word = String(currentWord.dropLast(2))
                word.append(horned.uIsUpper ? "U" : "u")
                word.append(lastIsUpper ? "O" : "o")
                word.append(newChar)
                return (word, true)
            }
            let wCancellationBases: [Character: Character] = ["ă": "a", "ơ": "o", "ư": "u"]
            if lower == "w", let base = wCancellationBases[lastLower] {
                let replacement = lastIsUpper ? Character(String(base).uppercased()) : base
                return replacingLast(in: currentWord, with: replacement, appending: newChar)
            }
            
            // dd -> đ / Đ
            if lower == "d" && lastLower == "d" {
                var word = currentWord
                word.removeLast()
                word.append(lastIsUpper && isUpper ? "Đ" : (lastIsUpper ? "Đ" : "đ"))
                return (word, true)
            }
            
            // aa -> â
            if lower == "a" && (lastLower == "a" || lastLower == "ă") {
                var word = currentWord
                word.removeLast()
                word.append(lastIsUpper ? "Â" : "â")
                return (word, true)
            }
            
            // ee -> ê
            if lower == "e" && lastLower == "e" {
                var word = currentWord
                word.removeLast()
                word.append(lastIsUpper ? "Ê" : "ê")
                return (word, true)
            }
            
            // oo -> ô
            if lower == "o" && (lastLower == "o" || lastLower == "ơ") {
                var word = currentWord
                word.removeLast()
                word.append(lastIsUpper ? "Ô" : "ô")
                return (word, true)
            }
            
            // w: aw -> ă, ow -> ơ, uw -> ư, uow -> ươ
            if lower == "w" {
                if lastLower == "a" {
                    var word = currentWord
                    word.removeLast()
                    word.append(lastIsUpper ? "Ă" : "ă")
                    return (word, true)
                } else if let pair = hornedUOPair(in: currentWord), !pair.isHorned {
                    // uo / ưo -> ươ (người, đường); "quo" stays "quơ".
                    var word = String(currentWord.dropLast(2))
                    word.append(pair.uIsUpper ? "Ư" : "ư")
                    word.append(lastIsUpper ? "Ơ" : "ơ")
                    return (word, true)
                } else if lastLower == "o" {
                    var word = currentWord
                    word.removeLast()
                    word.append(lastIsUpper ? "Ơ" : "ơ")
                    return (word, true)
                } else if lastLower == "u" {
                    var word = currentWord
                    word.removeLast()
                    word.append(lastIsUpper ? "Ư" : "ư")
                    return (word, true)
                } else if let shaped = hornNucleus(of: currentWord, typed: newChar, modern: modern) {
                    return (shaped, true)
                }
            }
        }
        
        // 2. Dấu thanh: s(sắc), f(huyền), r(hỏi), x(ngã), j(nặng), z(xóa dấu)
        var tone: ToneMarkType?
        switch lower {
        case "s": tone = .acute
        case "f": tone = .grave
        case "r": tone = .hook
        case "x": tone = .tilde
        case "j": tone = .dot
        case "z": tone = ToneMarkType.none
        default: tone = nil
        }
        
        if let targetTone = tone {
            if targetTone != .none && containsTone(targetTone, in: currentWord) {
                return (removingTones(from: currentWord) + String(newChar), true)
            }
            let (newWord, success) = applyTone(to: currentWord, tone: targetTone, modern: modern)
            if success {
                return (newWord, true)
            }
        }
        
        return (currentWord + String(newChar), false)
    }
    
    private func processVNI(currentWord: String, newChar: Character, modern: Bool) -> (String, Bool) {
        guard let num = Int(String(newChar)) else {
            return (currentWord + String(newChar), false)
        }
        
        // 1: sắc, 2: huyền, 3: hỏi, 4: ngã, 5: nặng, 0: xóa dấu
        if (1...5).contains(num) || num == 0 {
            let toneMapVNI: [Int: ToneMarkType] = [
                1: .acute, 2: .grave, 3: .hook, 4: .tilde, 5: .dot, 0: .none
            ]
            if let targetTone = toneMapVNI[num] {
                if targetTone != .none && containsTone(targetTone, in: currentWord) {
                    return (removingTones(from: currentWord) + String(newChar), true)
                }
                let (newWord, success) = applyTone(to: currentWord, tone: targetTone, modern: modern)
                if success {
                    return (newWord, true)
                }
            }
        }
        
        // 6: mũ (â, ê, ô), 7: móc (ơ, ư), 8: trăng (ă), 9: gạch (đ)
        if !currentWord.isEmpty {
            let lastChar = currentWord.last!
            let lastLower = Character(lastChar.lowercased())
            let lastIsUpper = lastChar.isUppercase

            // Repeating a VNI transformation digit cancels the conversion and
            // keeps that digit literal, matching the Telex escape behavior.
            let vniCancellationBases: [Int: [Character: Character]] = [
                6: ["â": "a", "ê": "e", "ô": "o"],
                7: ["ơ": "o", "ư": "u"],
                8: ["ă": "a"],
                9: ["đ": "d"]
            ]
            if let base = vniCancellationBases[num]?[lastLower] {
                let replacement = lastIsUpper ? Character(String(base).uppercased()) : base
                return replacingLast(in: currentWord, with: replacement, appending: newChar)
            }
            
            if num == 9 && lastLower == "d" {
                var word = currentWord
                word.removeLast()
                word.append(lastIsUpper ? "Đ" : "đ")
                return (word, true)
            }
            if num == 6 {
                if lastLower == "a" {
                    var word = currentWord; word.removeLast(); word.append(lastIsUpper ? "Â" : "â"); return (word, true)
                } else if lastLower == "e" {
                    var word = currentWord; word.removeLast(); word.append(lastIsUpper ? "Ê" : "ê"); return (word, true)
                } else if lastLower == "o" {
                    var word = currentWord; word.removeLast(); word.append(lastIsUpper ? "Ô" : "ô"); return (word, true)
                }
            }
            if num == 7 {
                if lastLower == "u" {
                    var word = currentWord; word.removeLast(); word.append(lastIsUpper ? "Ư" : "ư"); return (word, true)
                } else if lastLower == "o" {
                    var word = currentWord; word.removeLast(); word.append(lastIsUpper ? "Ơ" : "ơ"); return (word, true)
                }
            }
            if num == 8 && lastLower == "a" {
                var word = currentWord; word.removeLast(); word.append(lastIsUpper ? "Ă" : "ă"); return (word, true)
            }
        }
        
        return (currentWord + String(newChar), false)
    }

    /// Detects a trailing u/ư + o/ơ cluster that Telex `w` should treat as one
    /// unit. `isHorned` means it is already "ươ". "qu" is an onset, so "quo"
    /// is not a cluster.
    private func hornedUOPair(in word: String) -> (isHorned: Bool, uIsUpper: Bool)? {
        let chars = Array(word)
        guard chars.count >= 2 else { return nil }
        let u = chars[chars.count - 2]
        let o = Character(chars[chars.count - 1].lowercased())
        let uLower = Character(u.lowercased())
        guard uLower == "u" || uLower == "ư", o == "o" || o == "ơ" else { return nil }
        if chars.count >= 3, chars[chars.count - 3].lowercased() == "q" { return nil }

        let isHorned = uLower == "ư" && o == "ơ"
        // "uơ" (huơ, thuở) is already final; only uo, ưo and ươ take part.
        if !isHorned && o == "ơ" { return nil }
        return (isHorned, u.isUppercase)
    }

    /// Telex `w` typed after the final consonant or a trailing glide, as fast
    /// typists do: tangw -> tăng, duongw -> dương, nguoiw -> ngươi,
    /// tạngw -> tặng. A second `w` undoes it: tăngw -> tangw. Only applies
    /// when what follows the vowel nucleus can end a Vietnamese syllable.
    private func hornNucleus(of word: String, typed: Character, modern: Bool) -> String? {
        var chars = Array(word)
        guard let last = chars.lastIndex(where: { isVowel(stripTone($0)) }) else { return nil }
        var start = last
        while start > 0, isVowel(stripTone(chars[start - 1])) { start -= 1 }
        let finals = String(chars[(last + 1)...]).lowercased()
        guard ["", "c", "ch", "m", "n", "ng", "nh", "p", "t"].contains(finals) else { return nil }

        let tone = chars.lazy.compactMap { self.reverseToneMap[$0]?.tone }.first
        for index in start...last { chars[index] = stripTone(chars[index]) }
        let lower = { (index: Int) in Character(String(chars[index]).lowercased()) }
        let nucleus = Array(start...last)
        // After "q" the u is part of the onset (quăng), never a horn target.
        let glideIndex = start > 0 && lower(start - 1) == "q" && lower(start) == "u" ? start : nil

        let horned: [Character: Character] = ["a": "ă", "o": "ơ", "u": "ư", "A": "Ă", "O": "Ơ", "U": "Ư"]
        let plain: [Character: Character] = ["ă": "a", "ơ": "o", "ư": "u", "Ă": "A", "Ơ": "O", "Ư": "U"]

        if nucleus.contains(where: { plain[chars[$0]] != nil }) {
            for index in nucleus { chars[index] = plain[chars[index]] ?? chars[index] }
            let reverted = String(chars) + String(typed)
            return tone.map { applyTone(to: reverted, tone: $0, modern: modern).0 } ?? reverted
        }

        let targets: [Int]
        if let u = nucleus.first(where: { $0 != glideIndex && $0 < last && lower($0) == "u" && lower($0 + 1) == "o" }) {
            targets = [u, u + 1]
        } else if let a = nucleus.first(where: { lower($0) == "a" }) {
            targets = [a]
        } else if let o = nucleus.first(where: { lower($0) == "o" }) {
            targets = [o]
        } else if let u = nucleus.first(where: { $0 != glideIndex && lower($0) == "u" }) {
            targets = [u]
        } else {
            return nil
        }
        for index in targets { chars[index] = horned[chars[index]] ?? chars[index] }
        let shaped = String(chars)
        return tone.map { applyTone(to: shaped, tone: $0, modern: modern).0 } ?? shaped
    }

    private func replacingLast(
        in word: String,
        with replacement: Character,
        appending character: Character
    ) -> (String, Bool) {
        var result = word
        result.removeLast()
        result.append(replacement)
        result.append(character)
        return (result, true)
    }

    private func containsTone(_ tone: ToneMarkType, in word: String) -> Bool {
        word.contains { reverseToneMap[$0]?.tone == tone }
    }

    private func removingTones(from word: String) -> String {
        String(word.map(stripTone))
    }
    
    /// Bỏ dấu thanh vào vị trí nguyên âm thích hợp nhất trong từ
    private func applyTone(to word: String, tone: ToneMarkType, modern: Bool) -> (String, Bool) {
        guard !word.isEmpty else { return (word, false) }
        
        var chars = Array(word)
        var vowelIndices: [Int] = []
        
        // Tìm các nguyên âm trong từ
        for (i, ch) in chars.enumerated() {
            let base = stripTone(ch)
            if isVowel(base) {
                vowelIndices.append(i)
            }
        }
        
        guard !vowelIndices.isEmpty else { return (word, false) }
        
        let targetIndex = toneTargetIndex(
            chars: chars,
            vowelIndices: vowelIndices,
            modern: modern
        )
        
        // Gỡ bỏ dấu thanh cũ của tất cả nguyên âm trong từ trước
        var modified = false
        for idx in vowelIndices {
            let base = stripTone(chars[idx])
            if base != chars[idx] {
                chars[idx] = base
                modified = true
            }
        }
        
        // Thêm dấu thanh mới vào nguyên âm đích
        if tone != .none {
            let baseChar = chars[targetIndex]
            if let toneDict = toneMap[baseChar], let charWithTone = toneDict[tone] {
                chars[targetIndex] = charWithTone
                return (String(chars), true)
            }
        }
        
        return (String(chars), modified)
    }

    private func toneTargetIndex(
        chars: [Character],
        vowelIndices: [Int],
        modern: Bool
    ) -> Int {
        guard vowelIndices.count > 1 else { return vowelIndices[0] }

        // A shaped vowel (ă, â, ê, ô, ơ, ư) owns the tone. In clusters such
        // as "ươ", Vietnamese places it on the last shaped vowel.
        let shapedVowels: Set<Character> = ["ă", "â", "ê", "ô", "ơ", "ư"]
        let shapedIndices = vowelIndices.filter {
            shapedVowels.contains(Character(String(stripTone(chars[$0])).lowercased()))
        }
        if let shapedIndex = shapedIndices.last {
            return shapedIndex
        }

        if vowelIndices.count == 2 {
            let first = vowelIndices[0]
            let second = vowelIndices[1]
            let pair = String([
                Character(String(stripTone(chars[first])).lowercased()),
                Character(String(stripTone(chars[second])).lowercased())
            ])

            // After q/g, u/i is a glide rather than the tone-bearing vowel.
            if first > 0 {
                let preceding = Character(String(chars[first - 1]).lowercased())
                if (preceding == "q" && pair.first == "u")
                    || (preceding == "g" && pair.first == "i") {
                    return second
                }
            }

            let hasFinalConsonant = second < chars.count - 1
            if hasFinalConsonant {
                return second
            }

            // The modern/traditional setting only changes these open vowel
            // clusters: hòa/hoà, hòe/hoè, thúy/thuý.
            if ["oa", "oe", "uy"].contains(pair) {
                return modern ? first : second
            }

            // Other open diphthongs carry the tone on the first vowel:
            // múa, méo, đói, etc.
            return first
        }

        // Three-vowel clusters without a shaped vowel normally carry the
        // tone in the middle (for example khuya).
        return vowelIndices[1]
    }
    
    /// Consonants a Vietnamese syllable may start with. "q" and "g" stand for
    /// "qu" and "gi", whose second letter is read as a vowel here. f/j/w/z/dz
    /// keep chat spellings working: zô, dzô, fải, jờ, wá.
    private static let onsetPrefixes: Set<String> = [
        "", "b", "c", "ch", "d", "đ", "g", "gh", "h", "k", "kh", "l", "m", "n", "ng", "ngh",
        "nh", "p", "ph", "q", "r", "s", "t", "th", "tr", "v", "x",
        "f", "j", "w", "z", "dz"
    ]

    private func hasVietnameseOnset(_ word: String) -> Bool {
        let onset = word.prefix { !isVowel(stripTone($0)) }.lowercased()
        return Self.onsetPrefixes.contains(onset)
    }

    private func isVowel(_ ch: Character) -> Bool {
        let v: Set<Character> = ["a", "ă", "â", "e", "ê", "i", "o", "ô", "ơ", "u", "ư", "y",
                                 "A", "Ă", "Â", "E", "Ê", "I", "O", "Ô", "Ơ", "U", "Ư", "Y"]
        return v.contains(ch)
    }
    
    private func stripTone(_ ch: Character) -> Character {
        if let pair = reverseToneMap[ch] {
            return pair.base
        }
        return ch
    }
}

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
        
        // Tìm nguyên âm đích nhận dấu thanh
        let targetIndex: Int
        if vowelIndices.count == 1 {
            targetIndex = vowelIndices[0]
        } else if vowelIndices.count == 2 {
            // Quy tắc đặt dấu với 2 nguyên âm:
            // Nếu có phụ âm cuối: đặt vào nguyên âm thứ hai (ví dụ: toán, hoàn, biến)
            // Nếu không có phụ âm cuối:
            //   - Chuẩn mới (modern): hòa, thúy, hỏa -> đặt vào nguyên âm thứ hai (oà hay òa: modern là òa, thúy là úy)
            //   - Chuẩn cũ: hoà, thuý -> đặt vào nguyên âm thứ nhất
            let hasFinalConsonant = (vowelIndices.last! < chars.count - 1)
            if hasFinalConsonant {
                targetIndex = vowelIndices[1]
            } else {
                targetIndex = modern ? vowelIndices[1] : vowelIndices[0]
            }
        } else {
            // Có 3 nguyên âm: ví dụ khuya, quyên -> thường ở giữa
            targetIndex = vowelIndices[1]
        }
        
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

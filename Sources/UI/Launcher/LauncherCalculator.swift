import Foundation

/// Bounded arithmetic only. Never evaluates expressions through a scripting runtime.
enum LauncherCalculator {
    static func result(for query: String) -> String? {
        var input = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let explicit = input.hasPrefix("=")
        if explicit { input.removeFirst() }
        guard !input.isEmpty, input.count <= 256,
              explicit || input.contains(where: { "+-*/×÷".contains($0) }) else { return nil }
        var parser = Parser(chars: Array(input))
        guard let value = parser.expression(), parser.finished, value.isFinite else { return nil }
        if value == 0 { return "0" }
        return String(format: "%.12g", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private struct Parser {
        let chars: [Character]
        var index = 0
        mutating func skipSpaces() { while index < chars.count && chars[index].isWhitespace { index += 1 } }
        mutating func take(_ choices: String) -> Character? {
            skipSpaces()
            guard index < chars.count, choices.contains(chars[index]) else { return nil }
            defer { index += 1 }
            return chars[index]
        }
        var finished: Bool { mutating get { skipSpaces(); return index == chars.count } }
        mutating func expression() -> Double? {
            guard var value = term() else { return nil }
            while let op = take("+-") {
                guard let next = term() else { return nil }
                value = op == "+" ? value + next : value - next
            }
            return value.isFinite ? value : nil
        }
        mutating func term() -> Double? {
            guard var value = factor() else { return nil }
            while let op = take("*/×÷") {
                guard let next = factor(), !("/÷".contains(op) && next == 0) else { return nil }
                value = "*×".contains(op) ? value * next : value / next
            }
            return value.isFinite ? value : nil
        }
        mutating func factor() -> Double? {
            if let sign = take("+-") {
                guard let value = factor() else { return nil }
                return sign == "-" ? -value : value
            }
            if take("(") != nil {
                guard let value = expression(), take(")") != nil else { return nil }
                return value
            }
            skipSpaces()
            let start = index
            while index < chars.count && "0123456789.".contains(chars[index]) { index += 1 }
            guard start < index else { return nil }
            return Double(String(chars[start..<index]))
        }
    }
}

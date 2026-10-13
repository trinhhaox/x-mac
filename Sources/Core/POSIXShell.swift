import Foundation

enum POSIXShell {
    /// Quote a single argument for `/bin/sh` so it cannot be interpreted as syntax.
    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    static func join(_ arguments: [String]) -> String {
        arguments.map(quote).joined(separator: " ")
    }
}

enum BSDDeviceName {
    static func isValid(_ name: String) -> Bool {
        let pattern = #"^disk[0-9]+(s[0-9]+)?$"#
        return name.range(of: pattern, options: .regularExpression) != nil
    }
}

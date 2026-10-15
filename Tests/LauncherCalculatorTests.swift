import Testing
@testable import Xmac

struct LauncherCalculatorTests {
    @Test func precedenceAndParentheses() {
        #expect(LauncherCalculator.result(for: "2 + 3 * 4") == "14")
        #expect(LauncherCalculator.result(for: "= (12 + 3) / 5") == "3")
        #expect(LauncherCalculator.result(for: "2 × -3 ÷ 4") == "-1.5")
        #expect(LauncherCalculator.result(for: "=42") == "42")
        #expect(LauncherCalculator.result(for: "0.1+0.2") == "0.3")
    }
    @Test func rejectsInvalidAndUnboundedInput() {
        for query in ["42", "=", "1/0", "1/(2-2)", "(1+2", "2+3)", "2abc+1", "1..2+3", "1 2+3", "2(3+4)", "=sqrt(4)", "=1,5", String(repeating: "(", count: 257)] {
            #expect(LauncherCalculator.result(for: query) == nil, "Rejected: \(query)")
        }
    }
    @Test func boundedNestingAndUnarySigns() {
        #expect(LauncherCalculator.result(for: String(repeating: "-", count: 250) + "1") == "1")
        #expect(LauncherCalculator.result(for: "= -0") == "0")
        #expect(LauncherCalculator.result(for: "= .5 + .25") == "0.75")
    }
}

import SwiftParser
import Testing

@testable import SwiftMutationTesting

@Suite("LoopConditions")
struct LoopConditionsTests {
    @Test("Given a while loop, when the conditions are collected, then the condition is in and the body is out")
    func aWhileConditionIsIn() {
        let code = "func f(_ n: Int) { var i = 0; while i < n { i += 1 } }"
        let conditions = LoopConditions(in: Parser.parse(source: code))

        #expect(conditions.contains(utf8Offset: offset(of: "i < n", in: code)))
        #expect(!conditions.contains(utf8Offset: offset(of: "i += 1", in: code)))
        #expect(!conditions.contains(utf8Offset: offset(of: "var i = 0", in: code)))
    }

    @Test("Given a repeat-while loop, when the conditions are collected, then its condition is in")
    func aRepeatConditionIsIn() {
        let code = "func f(_ n: Int) { var i = 0; repeat { i += 1 } while i < n }"
        let conditions = LoopConditions(in: Parser.parse(source: code))

        #expect(conditions.contains(utf8Offset: offset(of: "i < n", in: code)))
        #expect(!conditions.contains(utf8Offset: offset(of: "i += 1", in: code)))
    }

    @Test("Given a while with several conditions, when collected, then every one of them is in")
    func everyConditionOfAWhileIsIn() {
        let code = "func f(_ a: [Int]) { var i = 0; while i < a.count, a[i] > 0 { i += 1 } }"
        let conditions = LoopConditions(in: Parser.parse(source: code))

        #expect(conditions.contains(utf8Offset: offset(of: "i < a.count", in: code)))
        #expect(conditions.contains(utf8Offset: offset(of: "a[i] > 0", in: code)))
    }

    @Test("Given a for-in loop and an if, when collected, then neither counts as a loop condition")
    func forInAndIfAreOut() {
        let code = "func f(_ a: [Int]) { for x in a where x > 0 { if x < 3 { print(x) } } }"
        let conditions = LoopConditions(in: Parser.parse(source: code))

        #expect(conditions.ranges.isEmpty)
        #expect(!conditions.contains(utf8Offset: offset(of: "x > 0", in: code)))
        #expect(!conditions.contains(utf8Offset: offset(of: "x < 3", in: code)))
    }

    // MARK: - Private

    private func offset(of text: String, in code: String) -> Int {
        code.utf8.distance(from: code.utf8.startIndex, to: code.range(of: text)!.lowerBound)
    }
}

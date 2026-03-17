import Testing

@testable import SwiftMutationTesting

@Suite("XCResultParser")
struct XCResultParserTests {
    @Test("Given valid xcresult JSON with test failure, when parsed, then returns killed with test name")
    func parsesValidXCResultJSON() {
        let json = """
            {
              "issues": {
                "testFailureSummaries": {
                  "_values": [
                    {
                      "testCaseName": {
                        "_value": "MySuite.myTest()"
                      }
                    }
                  ]
                }
              }
            }
            """

        let result = XCResultParser().parse(json)

        guard case .killed(let name) = result else {
            Issue.record("Expected .killed but got \(result)")
            return
        }
        #expect(name == "MySuite.myTest()")
    }

    @Test("Given JSON missing testCaseName, when parsed, then returns crashed")
    func parsesInvalidStructureAsCrashed() {
        let json = #"{"issues":{}}"#

        let result = XCResultParser().parse(json)

        #expect(result == .crashed)
    }

    @Test("Given malformed JSON, when parsed, then returns crashed")
    func parsesMalformedJSONAsCrashed() {
        let result = XCResultParser().parse("not json")

        #expect(result == .crashed)
    }
}

extension XCResultParser.Result: Equatable {
    public static func == (lhs: XCResultParser.Result, rhs: XCResultParser.Result) -> Bool {
        switch (lhs, rhs) {
        case (.killed(let lhsName), .killed(let rhsName)): return lhsName == rhsName
        case (.crashed, .crashed): return true
        default: return false
        }
    }
}

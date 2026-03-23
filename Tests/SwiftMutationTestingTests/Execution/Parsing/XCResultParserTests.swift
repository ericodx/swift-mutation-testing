import Testing

@testable import SwiftMutationTesting

@Suite("XCResultParser")
struct XCResultParserTests {
    @Test("Given test-results JSON with failed test case, when parsed, then returns killed with nodeIdentifier")
    func parsesFailedTestCase() {
        let json = """
            {
              "testNodes": [
                {
                  "nodeType": "Test Suite",
                  "name": "MySuite",
                  "result": "Failed",
                  "children": [
                    {
                      "nodeType": "Test Case",
                      "name": "myTest()",
                      "nodeIdentifier": "MySuite/myTest()",
                      "result": "Failed"
                    }
                  ]
                }
              ]
            }
            """

        let result = XCResultParser().parse(json)

        guard case .killed(let name) = result else {
            Issue.record("Expected .killed but got \(result)")
            return
        }
        #expect(name == "MySuite/myTest()")
    }

    @Test("Given test-results JSON with deeply nested failed test case, when parsed, then returns killed")
    func parsesDeeplyNestedFailedTestCase() {
        let json = """
            {
              "testNodes": [
                {
                  "nodeType": "Unit test bundle",
                  "name": "MyTests",
                  "result": "Failed",
                  "children": [
                    {
                      "nodeType": "Test Suite",
                      "name": "MySuite",
                      "result": "Failed",
                      "children": [
                        {
                          "nodeType": "Test Case",
                          "name": "myTest()",
                          "nodeIdentifier": "MySuite/myTest()",
                          "result": "Failed"
                        }
                      ]
                    }
                  ]
                }
              ]
            }
            """

        let result = XCResultParser().parse(json)

        guard case .killed(let name) = result else {
            Issue.record("Expected .killed but got \(result)")
            return
        }
        #expect(name == "MySuite/myTest()")
    }

    @Test("Given test-results JSON with no failed test cases, when parsed, then returns crashed")
    func parsesNoFailuresAsCrashed() {
        let json = """
            {
              "testNodes": [
                {
                  "nodeType": "Test Suite",
                  "name": "MySuite",
                  "result": "Passed"
                }
              ]
            }
            """

        let result = XCResultParser().parse(json)

        #expect(result == .crashed)
    }

    @Test("Given JSON missing testNodes, when parsed, then returns crashed")
    func parsesMissingTestNodesAsCrashed() {
        let result = XCResultParser().parse("{}")

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

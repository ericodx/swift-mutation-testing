import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("TestCoverage — Xcode console")
struct TestCoverageXcodeTests {
    private let record = SupportDeclarations.reachedMarker + " abcd1234:9"
    private let bundle = "Test Suite 'AppTests.xctest' started at 2026-11-03 23:29:24.612."
    private let parser = CoverageOutputParser(xcodeTargets: ["AppTestsModule": "AppTests", "AppTests": "AppTests"])

    private func parse(_ lines: [String]) -> TestCoverage {
        parser.parse(lines.joined(separator: "\n"))
    }

    private func tests(_ coverage: TestCoverage) -> [String] {
        coverage.sites["abcd1234:9"]?.map(\.id) ?? []
    }

    @Test("Given XCTest lines glued to output barriers, when parsed, then the test is Target/Class/method")
    func xctestLinesNameTheTargetClassAndMethod() {
        let coverage = parse([
            bundle,
            "XCTestOutputBarrierTest Case '-[AppTestsModule.AddTests testAdd]' started.",
            "XCTestOutputBarrier" + record,
            "Test Case '-[AppTestsModule.AddTests testAdd]' passed (0.002 seconds).",
            record,
        ])

        #expect(tests(coverage) == ["AppTests/AddTests/testAdd"])
        #expect(coverage.sites["abcd1234:9"]?.first?.library == .xctest)
        #expect(coverage.outside == ["abcd1234:9"])
    }

    @Test("Given a Swift Testing test inside nested suites, when parsed, then the id carries the suite path")
    func nestedSuitesMakeThePath() {
        let coverage = parse([
            bundle, "◇ Test run started.", record,
            "◇ Suite Outer started.", "◇ Suite Inner started.", "◇ Test innerTest() started.", record,
            "✔ Test innerTest() passed after 0.001 seconds.", "✔ Suite Inner passed after 0.001 seconds.",
            "◇ Test outerTest() started.", record, "✔ Test outerTest() passed after 0.001 seconds.",
            "✔ Suite Outer passed after 0.001 seconds.", "◇ Test top() started.", record,
            "✔ Test top() passed after 0.001 seconds.",
        ])

        #expect(tests(coverage) == ["AppTests/Outer/Inner/innerTest()", "AppTests/Outer/outerTest()", "AppTests/top()"])
        #expect(coverage.sites["abcd1234:9"]?.allSatisfy { $0.library == .swiftTesting } == true)
        #expect(coverage.outside == ["abcd1234:9"])
    }

    @Test("Given a display-named test, when parsed, then its records belong to the enclosing suite")
    func aDisplayNamedTestIsItsSuite() {
        let coverage = parse([
            bundle, "◇ Suite Outer started.", "◇ Test \"a display name\" started.", record,
            "✔ Test \"a display name\" passed after 0.001 seconds.", "✔ Suite Outer passed after 0.001 seconds.",
            "◇ Test \"top level\" started.", record, "✔ Test \"top level\" passed after 0.001 seconds.",
        ])

        #expect(tests(coverage) == ["AppTests/Outer", "AppTests"])
    }

    @Test("Given a display-named suite, when parsed, then tests inside it belong to the last named ancestor")
    func aDisplayNamedSuiteStopsThePath() {
        let coverage = parse([
            bundle, "◇ Suite Outer started.", "◇ Suite \"named\" started.", "◇ Suite Inner started.",
            "◇ Test deep() started.", record, "✔ Test deep() passed after 0.001 seconds.",
            "✔ Suite Inner passed after 0.001 seconds.", "✔ Suite \"named\" passed after 0.001 seconds.",
            "◇ Test shallow() started.", record, "✔ Test shallow() passed after 0.001 seconds.",
            "✔ Suite Outer passed after 0.001 seconds.",
        ])

        #expect(tests(coverage) == ["AppTests/Outer", "AppTests/Outer/shallow()"])
    }

    @Test("Given an issue line before a test fails, when parsed, then the test is still running until it fails")
    func anIssueLineDoesNotEndTheTest() {
        let coverage = parse([
            bundle, "◇ Test failing() started.", "✘ Test failing() recorded an issue at A.swift:3:9: Expectation failed",
            record, "✘ Test failing() failed after 0.001 seconds with 1 issue.", record,
        ])

        #expect(tests(coverage) == ["AppTests/failing()"])
        #expect(coverage.outside == ["abcd1234:9"])
    }

    @Test("Given a bundle the xctestrun names differently, when parsed, then the blueprint name is used")
    func theBundleIsMappedToItsTarget() {
        let parser = CoverageOutputParser(xcodeTargets: ["App Tests": "AppTests"])
        let lines = ["Test Suite 'App Tests.xctest' started at 2026-11-03.", "◇ Test t() started.", record]
        let coverage = parser.parse(lines.joined(separator: "\n"))

        #expect(coverage.sites["abcd1234:9"]?.map(\.id) == ["AppTests/t()"])
    }

    @Test("Given a Swift Testing-only bundle, when parsed, then the ids have no target until the xcresult names it")
    func aBundleWithoutXCTestLeavesTheTargetToTheXcresult() {
        let coverage = parse([
            "Test Suite 'All tests' started at 2026-11-03.", "◇ Test run started.", "◇ Suite Outer started.",
            "◇ Test deep() started.", record, "✔ Test deep() passed after 0.001 seconds.",
            "✔ Suite Outer passed after 0.001 seconds.", "◇ Test \"named\" started.", record,
            "✔ Test \"named\" passed after 0.001 seconds.",
        ])

        #expect(tests(coverage) == ["/Outer/deep()", "/"])

        let resolved = coverage.resolvingTargets(
            identifiers: ["AppTests/Outer/deep()", "UITests/Outer/deep()", "AppTests/top()"], targets: []
        )

        #expect(tests(resolved) == ["AppTests/Outer/deep()", "UITests/Outer/deep()", "AppTests", "UITests"])
    }

    @Test("Given an id the xcresult does not list, when targets are resolved, then the only target is used or it goes")
    func anUnlistedIdFallsBackToTheOnlyTarget() {
        var coverage = TestCoverage()
        coverage.sites["abcd1234:9"] = [
            TestReference(library: .swiftTesting, id: "/lost()"), TestReference(library: .xctest, id: "AppTests/C/t"),
        ]

        let one = coverage.resolvingTargets(identifiers: [], targets: ["AppTests"])
        #expect(tests(one) == ["AppTests/lost()", "AppTests/C/t"])

        let many = coverage.resolvingTargets(identifiers: ["UITests/other()"], targets: ["AppTests", "UITests"])
        #expect(tests(many) == ["AppTests/C/t"])
    }

    @Test("Given reaching tests and a test target, when the arguments are built, then each test is selected")
    func onlyTestingListsTheReachingTests() {
        let reaching = [
            TestReference(library: .swiftTesting, id: "AppTests/Outer/a()"),
            TestReference(library: .xctest, id: "OtherTests/C/testB"),
        ]

        #expect(
            TestExecutionStage.onlyTesting(reaching: reaching, testTarget: nil)
                == ["-only-testing", "AppTests/Outer/a()", "-only-testing", "OtherTests/C/testB"]
        )
        #expect(
            TestExecutionStage.onlyTesting(reaching: reaching, testTarget: "AppTests")
                == ["-only-testing", "AppTests/Outer/a()"]
        )
        #expect(
            TestExecutionStage.onlyTesting(reaching: reaching, testTarget: "ThirdTests")
                == ["-only-testing", "ThirdTests"]
        )
        #expect(TestExecutionStage.onlyTesting(reaching: nil, testTarget: nil) == [])
    }
}

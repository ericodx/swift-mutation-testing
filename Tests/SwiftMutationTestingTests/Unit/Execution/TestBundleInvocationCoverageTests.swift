import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("TestBundleInvocation — coverage")
struct TestBundleInvocationCoverageTests {
    private let invocation = TestBundleInvocation(
        bundleURL: URL(fileURLWithPath: "/sandbox/.build/out/Products/Debug/PkgTests.xctest"), framework: .xctest
    )
    private let reaching = [
        TestReference(library: .xctest, id: "PkgTests.AddTests/testAdd"),
        TestReference(library: .xctest, id: "PkgTests.AddTests/testMore"),
        TestReference(library: .swiftTesting, id: "PkgTests.AddSuite/plus()"),
    ]

    private func requests(
        _ tests: [TestReference], libraries: Set<TestingFramework> = [.xctest, .swiftTesting]
    ) -> [ProcessRequest] {
        invocation.requests(
            filter: "Ignored", mutantID: "m0", workingDirectory: URL(fileURLWithPath: "/sandbox"), timeout: 30,
            options: TestBundleInvocation.Options(libraries: libraries, reaching: tests)
        )
    }

    @Test("Given reaching tests of both libraries, when requests are built, then each library gets its own list")
    func eachLibraryGetsItsTests() throws {
        let built = requests(reaching)

        #expect(built.count == 2)
        let xctest = try #require(built.first { $0.arguments.first == "xctest" })
        #expect(xctest.arguments.contains("-XCTest"))
        #expect(xctest.arguments.contains("PkgTests.AddTests/testAdd,PkgTests.AddTests/testMore"))
        #expect(!xctest.arguments.contains("Ignored"))
        let swiftTesting = try #require(built.first { $0.arguments.first != "xctest" })
        #expect(swiftTesting.arguments.contains("^PkgTests\\.AddSuite\\/plus\\(\\)/"))
        #expect(!swiftTesting.arguments.contains("Ignored"))
    }

    @Test("Given reaching tests of one library only, when requests are built, then the other library is not run")
    func aLibraryWithNoReachingTestIsSkipped() {
        let built = requests(reaching.filter { $0.library == .xctest })

        #expect(built.map { $0.arguments.first } == ["xctest"])
    }

    @Test("Given no reaching test at all, when requests are built, then nothing runs")
    func noReachingTestRunsNothing() {
        #expect(requests([]).isEmpty)
    }

    @Test("Given several Swift Testing tests, when requests are built, then each is its own anchored filter")
    func everySwiftTestingTestIsAnAnchoredFilter() throws {
        let tests = [
            TestReference(library: .swiftTesting, id: "PkgTests.S/a()"),
            TestReference(library: .swiftTesting, id: "PkgTests.S/b(x:)"),
        ]

        let request = try #require(requests(tests).first)

        let arguments = request.arguments
        let filters = arguments.enumerated().filter { $1 == "--filter" }.map { arguments[$0.offset + 1] }
        #expect(filters == ["^PkgTests\\.S\\/a\\(\\)/", "^PkgTests\\.S\\/b\\(x:\\)/"])
    }

    @Test("Given collection, when requests are built, then each captures its output in the coverage file it names")
    func collectionSetsTheVariableAndTheEventStream() throws {
        let directory = URL(fileURLWithPath: "/coverage")
        let built = invocation.requests(
            filter: nil, mutantID: "", workingDirectory: URL(fileURLWithPath: "/sandbox"), timeout: 30,
            options: TestBundleInvocation.Options(coverageDirectory: directory)
        )

        #expect(built.count == 2)
        let files = built.map { $0.additionalEnvironment[SupportDeclarations.coverageEnvironmentVariable] }
        #expect(files.allSatisfy { $0?.hasPrefix("/coverage/coverage-") == true })
        #expect(built.map { $0.outputURL?.path } == files)
        #expect(Set(files).count == 2)
        let swiftTesting = try #require(built.first { $0.arguments.first != "xctest" })
        #expect(swiftTesting.arguments.contains("--no-parallel"))
        #expect(swiftTesting.arguments.contains("/dev/fd/2"))
        let xctest = try #require(built.first { $0.arguments.first == "xctest" })
        #expect(!xctest.arguments.contains("--no-parallel"))
    }

    @Test("Given no collection, when requests are built, then the variable is absent")
    func withoutCollectionTheVariableIsAbsent() {
        let built = invocation.requests(
            filter: nil, mutantID: "m0", workingDirectory: URL(fileURLWithPath: "/sandbox"), timeout: 30
        )

        #expect(built.allSatisfy { $0.additionalEnvironment[SupportDeclarations.coverageEnvironmentVariable] == nil })
    }
}

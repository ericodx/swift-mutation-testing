import Foundation
import Testing

@testable import SwiftMutationTesting

@Suite("TestBundleInvocation")
struct TestBundleInvocationTests {

    @Test("Given no built bundle, when looked up, then none is found")
    func findsNoBundleInAnEmptySandbox() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        #expect(TestBundleInvocation.bundleURL(in: Sandbox(rootURL: dir)) == nil)
    }

    @Test("Given a built bundle, when looked up, then it is found")
    func findsTheBundle() throws {
        let dir = try FileHelpers.makeTemporaryDirectory()
        defer { FileHelpers.cleanup(dir) }

        let products = dir.appendingPathComponent(".build/out/Products/Debug")
        try FileManager.default.createDirectory(
            at: products.appendingPathComponent("PkgTests.xctest"),
            withIntermediateDirectories: true
        )

        let found = TestBundleInvocation.bundleURL(in: Sandbox(rootURL: dir))

        #expect(found?.lastPathComponent == "PkgTests.xctest")
    }

    @Test("Given XCTest, when a request is built, then xctest runs the bundle with the mutant selected")
    func xctestRunsTheBundle() throws {
        let invocation = TestBundleInvocation(
            bundleURL: URL(fileURLWithPath: "/sandbox/.build/out/Products/Debug/PkgTests.xctest"),
            framework: .xctest
        )

        let request = try #require(
            invocation.requests(
                filter: nil,
                mutantID: "swift-mutation-testing_3",
                workingDirectory: URL(fileURLWithPath: "/sandbox"),
                timeout: 30
            ).first
        )

        #expect(request.executableURL.lastPathComponent == "xcrun")
        #expect(request.arguments.first == "xctest")
        #expect(request.arguments.last == "/sandbox/.build/out/Products/Debug/PkgTests.xctest")
        #expect(request.additionalEnvironment["__SWIFT_MUTATION_TESTING_ACTIVE"] == "swift-mutation-testing_3")
    }

    @Test("Given XCTest and a filter, when a request is built, then it is passed as -XCTest")
    func xctestPassesTheFilter() throws {
        let invocation = TestBundleInvocation(
            bundleURL: URL(fileURLWithPath: "/sandbox/PkgTests.xctest"),
            framework: .xctest
        )

        let request = try #require(
            invocation.requests(
                filter: "PkgTests", mutantID: "m0",
                workingDirectory: URL(fileURLWithPath: "/sandbox"), timeout: 30
            ).first
        )

        #expect(request.arguments.contains("-XCTest"))
        #expect(request.arguments.contains("PkgTests"))
    }

    @Test("Given Swift Testing, when a request is built, then the helper runs the bundle's executable")
    func swiftTestingUsesTheHelper() throws {
        let invocation = TestBundleInvocation(
            bundleURL: URL(fileURLWithPath: "/sandbox/PkgTests.xctest"),
            framework: .swiftTesting
        )

        let request = try #require(
            invocation.requests(
                filter: "PkgTests", mutantID: "m0",
                workingDirectory: URL(fileURLWithPath: "/sandbox"), timeout: 30
            ).first
        )

        #expect(request.executableURL.lastPathComponent == "swiftpm-testing-helper")
        #expect(request.arguments.contains("--test-bundle-path"))
        #expect(request.arguments.contains("/sandbox/PkgTests.xctest/Contents/MacOS/PkgTests"))
        #expect(request.arguments.contains("swift-testing"))
        #expect(request.arguments.contains("--filter"))
    }

    @Test("Given Swift Testing, when a request is built, then the developer library paths are set")
    func swiftTestingSuppliesLibraryPaths() throws {
        let invocation = TestBundleInvocation(
            bundleURL: URL(fileURLWithPath: "/sandbox/PkgTests.xctest"),
            framework: .swiftTesting
        )

        let request = try #require(
            invocation.requests(
                filter: nil, mutantID: "m0",
                workingDirectory: URL(fileURLWithPath: "/sandbox"), timeout: 30
            ).first
        )

        // Without these the helper cannot dlopen the bundle; `swift test` would have set them.
        #expect(request.additionalEnvironment["DYLD_FRAMEWORK_PATH"]?.hasSuffix("Library/Frameworks") == true)
        #expect(request.additionalEnvironment["DYLD_LIBRARY_PATH"]?.hasSuffix("Developer/usr/lib") == true)
    }

    @Test("Given either framework, when requests are built, then both testing libraries are run")
    func runsBothTestingLibraries() {
        for framework in [TestingFramework.xctest, .swiftTesting] {
            let requests = TestBundleInvocation(
                bundleURL: URL(fileURLWithPath: "/sandbox/PkgTests.xctest"),
                framework: framework
            ).requests(
                filter: nil, mutantID: "m0",
                workingDirectory: URL(fileURLWithPath: "/sandbox"), timeout: 30
            )

            // A package can hold both; running only one would skip the other's tests and report
            // mutants as survivors.
            #expect(requests.count == 2, "\(framework) should still run both libraries")
            #expect(requests.contains { $0.executableURL.lastPathComponent == "xcrun" })
            #expect(requests.contains { $0.executableURL.lastPathComponent == "swiftpm-testing-helper" })
        }
    }

    @Test("Given the selected Xcode, when the toolchain is resolved, then the helper exists")
    func toolchainPathsResolveOnThisMachine() {
        #expect(!DeveloperToolchain.developerPath.isEmpty)
        #expect(FileManager.default.fileExists(atPath: DeveloperToolchain.testingHelperPath))
        #expect(FileManager.default.fileExists(atPath: DeveloperToolchain.frameworksPath))
        #expect(FileManager.default.fileExists(atPath: DeveloperToolchain.librariesPath))
    }
}

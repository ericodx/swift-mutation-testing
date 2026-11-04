import Foundation

struct TestBundle: Sendable, Equatable {
    static let allLibraries: Set<TestingFramework> = [.xctest, .swiftTesting]

    let url: URL
    var libraries: Set<TestingFramework>

    var name: String {
        url.deletingPathExtension().lastPathComponent
    }
}

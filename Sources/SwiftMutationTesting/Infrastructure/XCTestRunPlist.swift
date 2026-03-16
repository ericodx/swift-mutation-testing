import Foundation

struct XCTestRunPlist: Sendable {
    init?(_ data: Data) {
        self.data = data
    }

    private let data: Data
}

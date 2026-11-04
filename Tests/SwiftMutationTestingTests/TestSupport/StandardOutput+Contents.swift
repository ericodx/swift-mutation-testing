@testable import SwiftMutationTesting

extension StandardOutput.Capture {
    var contents: String {
        buffer.withLock { $0 }
    }
}

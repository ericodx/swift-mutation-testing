import Foundation

@testable import SwiftMutationTesting

extension TestRunOutcome: Equatable {
    public static func == (lhs: TestRunOutcome, rhs: TestRunOutcome) -> Bool {
        switch (lhs, rhs) {
        case (.testsFailed(let lhsName), .testsFailed(let rhsName)): return lhsName == rhsName
        case (.testsSucceeded, .testsSucceeded): return true
        case (.crashed, .crashed): return true
        case (.timedOut, .timedOut): return true
        case (.buildFailed, .buildFailed): return true
        case (.unviable, .unviable): return true
        default: return false
        }
    }
}

@testable import SwiftMutationTesting

extension TestOutputParser.Result: Equatable {
    public static func == (lhs: TestOutputParser.Result, rhs: TestOutputParser.Result) -> Bool {
        switch (lhs, rhs) {
        case (.killed(let lhsName), .killed(let rhsName)): return lhsName == rhsName
        case (.crashed, .crashed): return true
        case (.unviable, .unviable): return true
        default: return false
        }
    }
}

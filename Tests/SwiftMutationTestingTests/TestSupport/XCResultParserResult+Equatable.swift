@testable import SwiftMutationTesting

extension XCResultParser.Result: Equatable {
    public static func == (lhs: XCResultParser.Result, rhs: XCResultParser.Result) -> Bool {
        switch (lhs, rhs) {
        case (.killed(let lhsName), .killed(let rhsName)): return lhsName == rhsName
        case (.crashed, .crashed): return true
        default: return false
        }
    }
}

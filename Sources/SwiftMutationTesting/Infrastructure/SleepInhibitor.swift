import Foundation
import IOKit.pwr_mgt

enum SleepInhibitor {

    static let reason = "swift-mutation-testing run"

    static func preventingIdleSleep<T>(
        reason: String = reason,
        _ body: () async throws -> T
    ) async rethrows -> T {
        let assertion = acquire(reason: reason)
        defer { IOPMAssertionRelease(assertion) }
        return try await body()
    }

    // MARK: - Private

    private static func acquire(reason: String) -> IOPMAssertionID {
        var id: IOPMAssertionID = 0
        _ = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )

        return id
    }
}

import Synchronization
import Testing

@testable import SwiftMutationTesting

@Suite("OnceWarning")
struct OnceWarningTests {
    @Test("Given a warning raised three times, when it is shown, then only the first message is written")
    func onlyTheFirstWarningIsWritten() {
        let written = Mutex<[String]>([])
        let warning = OnceWarning { line in written.withLock { $0.append(line) } }

        warning("first")
        warning("second")
        warning("third")

        #expect(written.withLock { $0 } == ["first"])
    }
}

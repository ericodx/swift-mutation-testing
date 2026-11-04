import Synchronization

enum StandardOutput {

    @TaskLocal static var capture: Capture?

    static func write(_ line: String = "") {
        if let capture {
            capture.append(line + "\n")
        } else {
            print(line)
        }
    }

    final class Capture: Sendable {
        let buffer = Mutex("")

        func append(_ text: String) {
            buffer.withLock { $0 += text }
        }
    }
}

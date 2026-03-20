import Foundation

actor ConsoleProgressReporter: ProgressReporter {
    private var lastFile: String?

    func report(_ event: RunnerEvent) async {
        switch event {
        case .discoveryFinished(let mutantCount, let schematizableCount, let incompatibleCount, let duration):
            let schema = "\(schematizableCount) schematizable"
            let extra = incompatibleCount > 0 ? ", \(incompatibleCount) incompatible" : ""
            let dur = String(format: "%.1f", duration)
            print("  ✓ Discovery: \(mutantCount) mutants (\(schema)\(extra)) in \(dur)s")

        case .buildStarted:
            print("")
            print("Building for testing...")

        case .buildFinished(let duration):
            print("  ✓ Built in \(String(format: "%.1f", duration))s")

        case .simulatorPoolReady(let size):
            print("  ✓ \(size) simulators ready")
            print("\nTesting mutants...")

        case .mutantStarted:
            break

        case .mutantFinished(let descriptor, let status, let index, let total):
            let file = URL(fileURLWithPath: descriptor.filePath).lastPathComponent
            if file != lastFile {
                if lastFile != nil { print("") }
                print("  \(file)")
                lastFile = file
            }
            print("    \(status.progressIcon) \(index)/\(total)  \(descriptor.operatorIdentifier)  :\(descriptor.line)")

        case .fallbackBuildStarted:
            break

        case .fallbackBuildFinished:
            break
        }
    }
}

extension ExecutionStatus {
    fileprivate var progressIcon: String {
        switch self {
        case .killed, .killedByCrash:
            return "✗"

        case .survived:
            return "~"

        case .unviable:
            return "⚠"

        case .timeout:
            return "⏱"

        case .noCoverage:
            return "–"
        }
    }
}

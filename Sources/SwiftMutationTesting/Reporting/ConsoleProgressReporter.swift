import Foundation

struct ConsoleProgressReporter: ProgressReporter {
    func report(_ event: RunnerEvent) async {
        switch event {
        case .buildStarted:
            print("Building for testing...")

        case .buildFinished(let duration):
            print("  ✓ Built in \(String(format: "%.1f", duration))s")

        case .simulatorPoolReady(let size):
            print("  ✓ \(size) simulators ready")

        case .mutantStarted:
            break

        case .mutantFinished(let descriptor, let status, let index, let total):
            let file = URL(fileURLWithPath: descriptor.filePath).lastPathComponent
            let operatorName = descriptor.operatorIdentifier
            let line = "  \(status.progressIcon) \(index)/\(total)  \(operatorName)  \(file):\(descriptor.line)"
            print(line)

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

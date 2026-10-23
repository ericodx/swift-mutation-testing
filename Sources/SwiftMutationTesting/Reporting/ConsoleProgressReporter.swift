import Foundation

actor ConsoleProgressReporter: ProgressReporter {
    func report(_ event: RunnerEvent) async {
        switch event {
        case .discoveryFinished(let mutantCount, let schematizableCount, let incompatibleCount, let duration):
            let schema = "\(schematizableCount) schematizable"
            let extra = incompatibleCount > 0 ? ", \(incompatibleCount) incompatible" : ""
            let dur = String(format: "%.1f", duration)
            StandardOutput.write("  ✓ Discovery: \(mutantCount) mutants (\(schema)\(extra)) in \(dur)s")

        case .loadedFromCache(let mutantCount):
            StandardOutput.write("  ✓ Loaded \(mutantCount) mutants from cache")

        case .schemaBatchStarted(let index, let count, let limit):
            StandardOutput.write("")
            StandardOutput.write("Schema batch \(index) of \(count) (at most \(limit) mutants per function):")

        case .buildStarted:
            StandardOutput.write("")
            StandardOutput.write("Building for testing...")

        case .buildFinished(let duration):
            StandardOutput.write("  ✓ Built in \(String(format: "%.1f", duration))s")

        case .schemaNarrowed(let excludedCount):
            let mutants =
                excludedCount == 1
                ? "1 mutant, to be built on its own"
                : "\(excludedCount) mutants, to be built one by one"
            StandardOutput.write("  ⚠ Schema did not build: retrying without \(mutants)")

        case .schemaSuiteFailed:
            StandardOutput.write(
                "  ⚠ The unmutated suite fails against the schema build but passes without it: "
                    + "building this batch's mutants one by one"
            )

        case .workersReady(let count, let usesSimulators):
            let unit = usesSimulators ? "simulator" : "worker"
            StandardOutput.write("  ✓ \(count) \(unit)\(count == 1 ? "" : "s") ready")
            StandardOutput.write("\nTesting mutants...")

        case .mutantStarted:
            break

        case .mutantFinished(let descriptor, let status, let index, let total):
            let file = URL(fileURLWithPath: descriptor.filePath).lastPathComponent
            let op = descriptor.operatorIdentifier
            StandardOutput.write("  \(status.progressIcon) \(index)/\(total)  \(op)  \(file):\(descriptor.line)")

        case .fallbackBuildStarted:
            break

        case .fallbackBuildFinished:
            break
        }
    }
}

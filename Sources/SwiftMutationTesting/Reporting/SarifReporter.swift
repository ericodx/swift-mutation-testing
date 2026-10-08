import Foundation

struct SarifReporter: Sendable {
    static let resultLimit = 25_000
    static let fingerprintKey = "swiftMutationTesting/v1"
    static let sourceRootBaseId = "%SRCROOT%"

    let outputPath: String
    let projectRoot: String
    var resultLimit = SarifReporter.resultLimit

    func report(_ summary: RunnerSummary) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(buildLog(summary))
        try data.write(to: URL(fileURLWithPath: outputPath))
    }

    func buildLog(_ summary: RunnerSummary) -> SarifLog {
        let undetected = RunnerSummary.byLocation(summary.undetected)

        if undetected.count > resultLimit {
            StandardError.write(
                "Warning: the SARIF report lists the first \(resultLimit) of \(undetected.count) undetected mutants, "
                    + "the most GitHub code scanning accepts"
            )
        }

        let reported = Array(undetected.prefix(resultLimit))
        let operators = Array(Set(reported.map(\.descriptor.operatorIdentifier))).sorted()
        var lines = SourceLines()
        let paths = ProjectRelativePath.Resolver(projectPath: projectRoot)

        let results = reported.map { result in
            sarifResult(
                for: result, ruleIndex: Self.position(of: result.descriptor.operatorIdentifier, in: operators),
                paths: paths,
                lines: &lines
            )
        }

        return SarifLog(
            runs: [
                SarifRun(
                    tool: SarifTool(
                        driver: SarifDriver(
                            name: Version.name,
                            version: Version.number,
                            informationUri: "https://github.com/ericodx/swift-mutation-testing",
                            rules: operators.map(SarifRuleCatalog.rule(for:))
                        )
                    ),
                    originalUriBaseIds: [
                        Self.sourceRootBaseId: SarifArtifactLocation(uri: URL(fileURLWithPath: rootPath).absoluteString)
                    ],
                    results: results
                )
            ]
        )
    }

    static func position(of identifier: String, in sorted: [String]) -> Int {
        var low = 0
        var high = sorted.count
        while low < high {
            let middle = (low + high) / 2
            if sorted[middle] < identifier { low = middle + 1 } else { high = middle }
        }
        return low
    }

    // MARK: - Private

    private var rootPath: String {
        let canonical = CanonicalPath.make(for: projectRoot)
        return canonical.hasSuffix("/") ? canonical : canonical + "/"
    }

    private func sarifResult(
        for result: ExecutionResult, ruleIndex: Int, paths: ProjectRelativePath.Resolver, lines: inout SourceLines
    ) -> SarifResult {
        let descriptor = result.descriptor
        let covered = result.status != .noCoverage
        let line = lines.line(descriptor.line, of: descriptor.filePath)
        let startColumn = utf16Column(utf8Column: descriptor.column, in: line)

        return SarifResult(
            ruleId: descriptor.operatorIdentifier,
            ruleIndex: ruleIndex,
            level: "warning",
            message: SarifMessage(
                text: "Mutant survived: \(descriptor.description). "
                    + (covered ? "No test failed when this code was changed." : "No test executed this code.")
            ),
            locations: [
                SarifLocation(
                    physicalLocation: SarifPhysicalLocation(
                        artifactLocation: SarifArtifactLocation(
                            uri: paths.make(for: descriptor.filePath),
                            uriBaseId: Self.sourceRootBaseId
                        ),
                        region: SarifRegion(
                            startLine: descriptor.line,
                            startColumn: startColumn,
                            endColumn: startColumn + descriptor.originalText.utf16.count
                        )
                    )
                )
            ],
            partialFingerprints: [Self.fingerprintKey: descriptor.fingerprint],
            properties: SarifResultProperties(
                mutationStatus: covered ? "survived" : "noCoverage",
                replacement: descriptor.mutatedText
            )
        )
    }

    private func utf16Column(utf8Column: Int, in line: String?) -> Int {
        guard
            let line,
            let prefix = String(bytes: Array(line.utf8.prefix(max(0, utf8Column - 1))), encoding: .utf8)
        else { return utf8Column }
        return prefix.utf16.count + 1
    }

    private struct SourceLines {
        private var cache: [String: [Substring]] = [:]

        mutating func line(_ number: Int, of path: String) -> String? {
            if cache[path] == nil {
                let content = try? String(contentsOfFile: path, encoding: .utf8)
                cache[path] = content?.split(separator: "\n", omittingEmptySubsequences: false) ?? []
            }
            guard let lines = cache[path], number >= 1, number <= lines.count else { return nil }
            return String(lines[number - 1])
        }
    }
}

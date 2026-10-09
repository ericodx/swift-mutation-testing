import Foundation

// The Xcode incompatible-mutant benchmark: time how long a version of the tool takes over the mutants that
// cannot be schematized, on a copy of Fixtures/CalcApp grown large enough for a build to cost something.
// Foundation only; run it with `swift benchmark.swift`.
//
//   fixture <out-dir> [--files <n>] [--source <CalcApp>]
//   run <fixture> <results-dir> --tool <swift-mutation-testing> --label <name> --destination <destination>
//       [--concurrency <n>] [--repetitions <n>]
//   summarize <results-dir> [--baseline <label>]
//   timings <fixture> --destination <destination> [--repetitions <n>] [--limit <seconds>]
//
// `fixture` copies CalcApp and adds <n> generated source files (300 by default) to its project, a
// Constants.swift of `static let` initialisers whose 11 mutations are all incompatible, a project that builds
// for macOS and the iOS Simulator, and Swift Testing tests (with XCTest the tool resolves concurrency to 1).
//
// `run` copies the fixture afresh for every repetition (3 by default), runs the tool under a pseudo-terminal
// so that its progress lines are not buffered, and stamps each line as it arrives. It records the whole run,
// the time before the first worker is ready, and the incompatible phase — from "Testing mutants..." to the
// last verdict — with the verdict counts, as <results-dir>/<label>-<n>/result.json. The tool runs with
// `--operator-tier experimental --timeout 300 --no-cache`, mutating Constants.swift only. On macOS the tool
// resolves an Xcode run's concurrency to 1; use the iOS Simulator to measure more than one worker.
//
// `summarize` prints the medians per label as a Markdown table, the change against --baseline (the first
// label otherwise), and refuses when two runs reached different verdicts, since their times do not compare.
//
// `timings` measures, with xcodebuild alone and on a copy of the fixture, what the warm sandboxes and the
// diagnostics flag save each mutant: a cold build-for-testing, an incremental one after a one-line change to
// Constants.swift, and a test-without-building that has a failing test, with and without
// `-collect-test-diagnostics never`. It prints the medians of <n> runs of each (3 by default). A run still going
// after --limit seconds (120 by default) is stopped and counted as "over the limit": a failing run that
// collects diagnostics on the simulator can take ten minutes.
//
// Comparing versions: build each one in a worktree of its own and pass its binary as --tool.
//
//   git worktree add --detach /tmp/smt-before <commit>
//   (cd /tmp/smt-before && swift build -c release --product swift-mutation-testing)
//   swift benchmark.swift run <fixture> <results> --tool /tmp/smt-before/.build/release/swift-mutation-testing \
//       --label before --destination "platform=iOS Simulator,name=iPhone 17" --concurrency 8
//
// A version older than `-collect-test-diagnostics never` must be given that flag before it is built, or its
// failing test runs collect a sysdiagnose each: on the simulator that doubles their time and now and then
// hangs them until the timeout, which says nothing about the code being compared. In the worktree, append
// `"-collect-test-diagnostics", "never",` after `"-parallel-testing-enabled", "NO",` in the incompatible
// executor's `test-without-building` arguments, and after `"-derivedDataPath", context.artifact.derivedDataPath,`
// in TestExecutionStage's, then build. Give every version compared the same flag.

// MARK: - Generating the fixture

func makeFixture(at directory: URL, from source: URL, fileCount: Int) throws {
    let fileManager = FileManager.default
    guard !fileManager.fileExists(atPath: directory.path) else {
        throw BenchmarkError("\(directory.path) already exists")
    }
    try fileManager.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fileManager.copyItem(at: source, to: directory)
    try? fileManager.removeItem(at: directory.appendingPathComponent(".swift-mutation-testing-cache"))

    let sources = directory.appendingPathComponent("Sources")
    let names = ["Constants.swift"] + (0 ..< fileCount).map { "Gen\($0).swift" }
    try constants.write(to: sources.appendingPathComponent("Constants.swift"), atomically: true, encoding: .utf8)
    for index in 0 ..< fileCount {
        try generated(index).write(
            to: sources.appendingPathComponent("Gen\(index).swift"), atomically: true, encoding: .utf8
        )
    }
    try tests.write(
        to: directory.appendingPathComponent("Tests/CalcAppTests.swift"), atomically: true, encoding: .utf8
    )

    let projectFile = directory.appendingPathComponent("CalcApp.xcodeproj/project.pbxproj")
    let project = try String(contentsOf: projectFile, encoding: .utf8)
    try addingFiles(names, to: project).write(to: projectFile, atomically: true, encoding: .utf8)
    print("Wrote \(directory.path): \(fileCount) generated files, 11 incompatible mutants in Constants.swift")
}

func addingFiles(_ names: [String], to project: String) throws -> String {
    var buildFiles = ""
    var fileReferences = ""
    var groupChildren = ""
    var sourcesPhase = ""
    for (index, name) in names.enumerated() {
        let reference = String(format: "BBBB%04X000000000000BBBB", index)
        let buildFile = String(format: "CCCC%04X000000000000CCCC", index)
        buildFiles +=
            "\t\t\(buildFile) /* \(name) in Sources */ = {isa = PBXBuildFile; fileRef = \(reference) /* \(name) */; };\n"
        fileReferences +=
            "\t\t\(reference) /* \(name) */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
            + "path = \(name); sourceTree = \"<group>\"; };\n"
        groupChildren += "\t\t\t\t\(reference) /* \(name) */,\n"
        sourcesPhase += "\t\t\t\t\(buildFile) /* \(name) in Sources */,\n"
    }

    let logicReference = "\t\t\t\tAAAA0013000000000000AAAA /* Logic.swift */,\n"
    let logicBuildFile = "\t\t\t\tAAAA0021000000000000AAAA /* Logic.swift in Sources */,\n"
    let multiplatform =
        "SDKROOT = auto;\n\t\t\t\tSUPPORTED_PLATFORMS = \"iphoneos iphonesimulator macosx\";\n"
        + "\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;\n\t\t\t\tTARGETED_DEVICE_FAMILY = \"1,2\";"
    let anchors = [
        "/* End PBXBuildFile section */", "/* End PBXFileReference section */", logicReference, logicBuildFile,
        "SDKROOT = macosx;",
    ]
    guard anchors.allSatisfy(project.contains) else {
        throw BenchmarkError("the CalcApp project no longer has the entries the generator extends")
    }

    return
        project
        .replacingOccurrences(
            of: "/* End PBXBuildFile section */", with: buildFiles + "/* End PBXBuildFile section */"
        )
        .replacingOccurrences(
            of: "/* End PBXFileReference section */", with: fileReferences + "/* End PBXFileReference section */"
        )
        .replacingOccurrences(of: logicReference, with: logicReference + groupChildren)
        .replacingOccurrences(of: logicBuildFile, with: logicBuildFile + sourcesPhase)
        .replacingOccurrences(of: "SDKROOT = macosx;", with: multiplatform)
}

let constants = """
    public enum Limits {
        public static let maximum = 90 + 10
        public static let minimum = 1 - 1
        public static let doubled = 21 * 2
        public static let spare = 7 + 1
        public static let strict = true
        public static let lenient = false
        public static let ordered = 3 > 2
        public static let both = true && false
    }

    """

let tests = """
    import Testing

    @testable import CalcApp

    @Test func add() { #expect(Calculator().add(2, 3) == 5) }
    @Test func subtract() { #expect(Calculator().subtract(5, 3) == 2) }
    @Test func positive() { #expect(Calculator().isPositive(1)) }
    @Test func inRange() { #expect(Validator().isInRange(50)) }
    @Test func maximum() { #expect(Limits.maximum == 100) }
    @Test func minimum() { #expect(Limits.minimum == 0) }
    @Test func doubled() { #expect(Limits.doubled == 42) }
    @Test func strict() { #expect(Limits.strict) }
    @Test func ordered() { #expect(Limits.ordered) }
    @Test func both() { #expect(!Limits.both) }
    @Test func generated() { #expect(Gen0(values: [3, 1, 2, 1]).sortedUnique() == [1, 2, 3]) }

    """

func generated(_ index: Int) -> String {
    """
    import Foundation

    public struct Gen\(index)<Element: Hashable & Comparable> {
        public let values: [Element]

        public init(values: [Element]) { self.values = values }

        public func sortedUnique() -> [Element] { Array(Set(values)).sorted() }
        public func pairs() -> [(Element, Element)] { Array(zip(values, values.dropFirst())) }
        public func indexed() -> [Int: Element] {
            Dictionary(uniqueKeysWithValues: values.enumerated().map { ($0.offset, $0.element) })
        }
        public func counts() -> [Element: Int] { values.reduce(into: [:]) { $0[$1, default: 0] += 1 } }
        public func chunks(of size: Int) -> [[Element]] {
            stride(from: 0, to: values.count, by: max(1, size)).map {
                Array(values[$0 ..< Swift.min($0 + max(1, size), values.count)])
            }
        }
        public func describe() -> String { values.map { "\\($0)" }.joined(separator: ",") }
        public func firstMatching(_ predicate: (Element) -> Bool) -> Element? { values.first(where: predicate) }
        public func partitioned(by pivot: Element) -> ([Element], [Element]) {
            (values.filter { $0 < pivot }, values.filter { $0 >= pivot })
        }
    }

    public enum Shape\(index): CaseIterable, Codable {
        case circle(radius: Double), square(side: Double), rectangle(width: Double, height: Double)

        public static var allCases: [Shape\(index)] {
            [.circle(radius: 1), .square(side: 2), .rectangle(width: 1, height: 2)]
        }

        public var area: Double {
            switch self {
            case .circle(let radius): return Double.pi * radius * radius
            case .square(let side): return side * side
            case .rectangle(let width, let height): return width * height
            }
        }
    }

    """
}

// MARK: - Running one version

struct RunResult: Codable {
    let label: String
    let repetition: Int
    let wall: Double
    let beforeTesting: Double
    let phase: Double
    let verdicts: [String: Int]
}

func run(
    fixture: URL, results: URL, tool: String, label: String, destination: String, concurrency: Int, repetitions: Int
) throws {
    for repetition in 1 ... repetitions {
        let directory = results.appendingPathComponent("\(label)-\(repetition)")
        let project = directory.appendingPathComponent("project")
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture, to: project)

        let report = directory.appendingPathComponent("report.json")
        let arguments =
            [
                "-q", "/dev/null", tool, "run", project.path,
                "--scheme", "CalcApp", "--destination", destination, "--concurrency", "\(concurrency)",
                "--operator-tier", "experimental", "--timeout", "300", "--no-cache", "--output", report.path,
            ]
            + ["/Sources/Gen", "/Calculator.swift", "/Validator.swift", "/Logic.swift"].flatMap { ["--exclude", $0] }

        let start = Date()
        let lines = try stampedLines(of: "/usr/bin/script", arguments)
        let end = Date()
        try lines.map { "\(String(format: "%.2f", $0.time.timeIntervalSince(start))) \($0.text)" }
            .joined(separator: "\n")
            .write(to: directory.appendingPathComponent("output.log"), atomically: true, encoding: .utf8)

        guard let testing = lines.first(where: { $0.text.contains("Testing mutants") })?.time else {
            throw BenchmarkError("\(label)-\(repetition) never reached the test phase; see its output.log")
        }
        let lastVerdict = lines.last { $0.text.range(of: #"\d+/\d+  "#, options: .regularExpression) != nil }?.time
        let result = RunResult(
            label: label,
            repetition: repetition,
            wall: end.timeIntervalSince(start),
            beforeTesting: testing.timeIntervalSince(start),
            phase: (lastVerdict ?? testing).timeIntervalSince(testing),
            verdicts: try verdicts(in: report)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(result).write(to: directory.appendingPathComponent("result.json"))
        print(
            "\(label)-\(repetition): whole run \(seconds(result.wall)), incompatible phase \(seconds(result.phase)), "
                + verdictLine(result.verdicts)
        )
    }
}

func stampedLines(of executable: String, _ arguments: [String]) throws -> [(time: Date, text: String)] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    let collected = Collected()
    pipe.fileHandleForReading.readabilityHandler = { handle in
        collected.append(handle.availableData)
    }
    try process.run()
    process.waitUntilExit()
    pipe.fileHandleForReading.readabilityHandler = nil
    collected.append(pipe.fileHandleForReading.readDataToEndOfFile())
    return collected.flushed()
}

final class Collected: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = Data()
    private var lines: [(time: Date, text: String)] = []

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        pending.append(data)
        while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
            let line = String(decoding: pending[pending.startIndex ..< newline], as: UTF8.self)
            lines.append((now, line.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))))
            pending.removeSubrange(pending.startIndex ... newline)
        }
    }

    func flushed() -> [(time: Date, text: String)] {
        lock.lock()
        defer { lock.unlock() }
        if !pending.isEmpty {
            lines.append((Date(), String(decoding: pending, as: UTF8.self)))
            pending.removeAll()
        }
        return lines
    }
}

func verdicts(in report: URL) throws -> [String: Int] {
    struct Report: Decodable {
        struct File: Decodable { let mutants: [Mutant] }
        struct Mutant: Decodable { let status: String }
        let files: [String: File]
    }
    let decoded = try JSONDecoder().decode(Report.self, from: Data(contentsOf: report))
    return decoded.files.values.flatMap(\.mutants).reduce(into: [:]) { $0[$1.status, default: 0] += 1 }
}

// MARK: - Summarizing

func summarize(results: URL, baseline: String?) throws {
    let decoder = JSONDecoder()
    let runs = try FileManager.default.contentsOfDirectory(at: results, includingPropertiesForKeys: nil)
        .map { $0.appendingPathComponent("result.json") }
        .filter { FileManager.default.fileExists(atPath: $0.path) }
        .map { try decoder.decode(RunResult.self, from: Data(contentsOf: $0)) }
    guard !runs.isEmpty else { throw BenchmarkError("no result.json under \(results.path)") }

    let distinctVerdicts = Set(runs.map { verdictLine($0.verdicts) })
    guard distinctVerdicts.count == 1 else {
        throw BenchmarkError(
            "the runs reached different verdicts, so their times do not compare:\n"
                + runs.map { "  \($0.label)-\($0.repetition): \(verdictLine($0.verdicts))" }.joined(separator: "\n")
        )
    }

    var labels: [String] = []
    for run in runs.sorted(by: { ($0.label, $0.repetition) < ($1.label, $1.repetition) })
    where !labels.contains(run.label) {
        labels.append(run.label)
    }
    let reference = baseline ?? labels[0]
    guard labels.contains(reference) else { throw BenchmarkError("no runs labelled '\(reference)'") }

    func medians(_ label: String) -> (phase: Double, wall: Double, count: Int) {
        let mine = runs.filter { $0.label == label }
        return (median(mine.map(\.phase)), median(mine.map(\.wall)), mine.count)
    }
    let base = medians(reference)

    print("Every run: \(distinctVerdicts.first ?? "")\n")
    print("| Version | Runs | Incompatible phase | Whole run |")
    print("|---|---|---|---|")
    for label in [reference] + labels.filter({ $0 != reference }) {
        let current = medians(label)
        let change =
            label == reference ? ("", "") : (change(current.phase, base.phase), change(current.wall, base.wall))
        print(
            "| \(label) | \(current.count) | \(seconds(current.phase))\(change.0) | \(seconds(current.wall))\(change.1) |"
        )
    }
}

func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    let middle = sorted.count / 2
    return sorted.count % 2 == 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
}

func change(_ value: Double, _ reference: Double) -> String {
    guard reference > 0 else { return "" }
    let percent = (value - reference) / reference * 100
    return String(format: " (%@%.0f%%)", percent >= 0 ? "+" : "−", abs(percent))
}

func seconds(_ value: Double) -> String {
    String(format: "%.1f s", value)
}

func verdictLine(_ verdicts: [String: Int]) -> String {
    verdicts.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: ", ")
}

// MARK: - Timing xcodebuild alone

func timings(fixture: URL, destination: String, repetitions: Int, limit: Double) throws {
    let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("smt-timings-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: scratch) }
    let project = scratch.appendingPathComponent("project")
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: fixture, to: project)
    let constants = project.appendingPathComponent("Sources/Constants.swift")
    let original = try String(contentsOf: constants, encoding: .utf8)

    func xcodebuild(_ action: [String], derivedData: URL) throws -> (seconds: Double, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments =
            ["xcodebuild"] + action
            + ["-scheme", "CalcApp", "-destination", destination, "-derivedDataPath", derivedData.path, "-quiet"]
        process.currentDirectoryURL = project
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let start = Date()
        try process.run()
        while process.isRunning, Date().timeIntervalSince(start) < limit {
            Thread.sleep(forTimeInterval: 0.2)
        }
        guard !process.isRunning else {
            process.terminate()
            process.waitUntilExit()
            return (.infinity, -1)
        }
        return (Date().timeIntervalSince(start), process.terminationStatus)
    }

    func shown(_ values: [Double]) -> String {
        let stopped = values.filter { $0 == .infinity }.count
        let value = median(values)
        let time = value == .infinity ? "over \(seconds(limit))" : seconds(value)
        return stopped == 0 ? time : "\(time) (\(stopped) of \(values.count) stopped at \(seconds(limit)))"
    }

    func setMaximum(_ expression: String) throws {
        try original.replacingOccurrences(of: "maximum = 90 + 10", with: "maximum = \(expression)")
            .write(to: constants, atomically: true, encoding: .utf8)
    }

    var cold: [Double] = []
    for repetition in 1 ... repetitions {
        let derivedData = scratch.appendingPathComponent("cold-\(repetition)")
        let build = try xcodebuild(["build-for-testing"], derivedData: derivedData)
        guard build.exitCode == 0 else { throw BenchmarkError("the fixture does not build for \(destination)") }
        cold.append(build.seconds)
    }

    let warm = scratch.appendingPathComponent("cold-1")
    _ = try xcodebuild(["build-for-testing"], derivedData: warm)
    var incremental: [Double] = []
    for repetition in 1 ... repetitions {
        try setMaximum(repetition % 2 == 0 ? "90 + 10" : "90 * 10")
        incremental.append(try xcodebuild(["build-for-testing"], derivedData: warm).seconds)
    }

    try setMaximum("90 - 10")
    _ = try xcodebuild(["build-for-testing"], derivedData: warm)
    var collecting: [Double] = []
    var skipping: [Double] = []
    for _ in 1 ... repetitions {
        let withDiagnostics = try xcodebuild(["test-without-building"], derivedData: warm)
        let withoutDiagnostics = try xcodebuild(
            ["test-without-building", "-collect-test-diagnostics", "never"], derivedData: warm
        )
        guard withDiagnostics.exitCode != 0, withoutDiagnostics.exitCode != 0 else {
            throw BenchmarkError("the mutated fixture's tests passed; the failing run measures nothing")
        }
        collecting.append(withDiagnostics.seconds)
        skipping.append(withoutDiagnostics.seconds)
    }

    print("Medians of \(repetitions) runs on \(destination):\n")
    print("| Step | Time |")
    print("|---|---|")
    print("| Cold build-for-testing | \(shown(cold)) |")
    print("| Incremental build-for-testing, one file changed | \(shown(incremental)) |")
    print("| Failing test-without-building, diagnostics collected | \(shown(collecting)) |")
    print("| Failing test-without-building, -collect-test-diagnostics never | \(shown(skipping)) |")
}

// MARK: - Helpers

struct BenchmarkError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func option(_ name: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

// MARK: - Entry point

setbuf(stdout, nil)

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first else {
        throw BenchmarkError("usage: benchmark.swift fixture|run|summarize|timings …")
    }
    let script = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()

    switch command {
    case "fixture":
        guard arguments.count >= 2 else {
            throw BenchmarkError("usage: fixture <out-dir> [--files <n>] [--source <CalcApp>]")
        }
        let source =
            option("--source", in: arguments).map { URL(fileURLWithPath: $0) }
            ?? script.appendingPathComponent("../../../Fixtures/CalcApp").standardizedFileURL
        try makeFixture(
            at: URL(fileURLWithPath: arguments[1]), from: source,
            fileCount: option("--files", in: arguments).flatMap(Int.init) ?? 300
        )

    case "run":
        guard
            arguments.count >= 3, let tool = option("--tool", in: arguments),
            let label = option("--label", in: arguments), let destination = option("--destination", in: arguments)
        else {
            throw BenchmarkError(
                "usage: run <fixture> <results-dir> --tool <binary> --label <name> --destination <destination> "
                    + "[--concurrency <n>] [--repetitions <n>]"
            )
        }
        try run(
            fixture: URL(fileURLWithPath: arguments[1]), results: URL(fileURLWithPath: arguments[2]),
            tool: tool, label: label, destination: destination,
            concurrency: option("--concurrency", in: arguments).flatMap(Int.init) ?? 1,
            repetitions: option("--repetitions", in: arguments).flatMap(Int.init) ?? 3
        )

    case "timings":
        guard arguments.count >= 2, let destination = option("--destination", in: arguments) else {
            throw BenchmarkError(
                "usage: timings <fixture> --destination <destination> [--repetitions <n>] [--limit <seconds>]")
        }
        try timings(
            fixture: URL(fileURLWithPath: arguments[1]), destination: destination,
            repetitions: option("--repetitions", in: arguments).flatMap(Int.init) ?? 3,
            limit: option("--limit", in: arguments).flatMap(Double.init) ?? 120
        )

    case "summarize":
        guard arguments.count >= 2 else { throw BenchmarkError("usage: summarize <results-dir> [--baseline <label>]") }
        try summarize(results: URL(fileURLWithPath: arguments[1]), baseline: option("--baseline", in: arguments))

    default:
        throw BenchmarkError("unknown command '\(command)'")
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}

import Foundation

// The operator campaign: run the tool over a fixed corpus, aggregate the reports per operator and per
// project, and draw the survivors to review by hand. Foundation only; run it with `swift campaign.swift`.
//
//   run <corpus.json> <out-dir> --tool <swift-mutation-testing>
//   aggregate <out-dir> --markdown <path> --csv <path> [--equivalence <csv>] [--min-mutants <n>]
//   sample <out-dir> --csv <path> [--seed <n>] [--per-cell <n>] [--force]
//   check                       aggregates the fixture in check/ and compares with its expected output

// MARK: - Report model (the Stryker JSON the tool writes)

struct Report: Decodable {
    let files: [String: ReportFile]
}

struct ReportFile: Decodable {
    let mutants: [Mutant]
}

struct Mutant: Decodable {
    let mutatorName: String
    let status: String
    let duration: Int?
    let fingerprint: String
    let originalText: String?
    let replacement: String?
    let location: Location

    struct Location: Decodable {
        let start: Position
    }

    struct Position: Decodable {
        let line: Int
    }
}

struct Project: Decodable {
    let name: String
    let repository: String
    let sha: String
    let arguments: [String]?
}

// MARK: - Metrics

struct Cell {
    var generated = 0
    var detected = 0
    var undetected = 0
    var noCoverage = 0
    var unviable = 0
    var durations: [Int] = []

    var killRate: Double? {
        let measured = detected + undetected
        return measured == 0 ? nil : Double(detected) / Double(measured) * 100
    }

    var unviablePercent: Double? {
        generated == 0 ? nil : Double(unviable) / Double(generated) * 100
    }

    var noCoveragePercent: Double? {
        generated == 0 ? nil : Double(noCoverage) / Double(generated) * 100
    }

    var costPerMutant: Double? {
        durations.isEmpty ? nil : Double(durations.reduce(0, +)) / Double(durations.count)
    }

    mutating func add(_ mutant: Mutant) {
        generated += 1
        switch mutant.status {
        case "Killed", "Timeout": detected += 1
        case "Survived": undetected += 1
        case "NoCoverage":
            undetected += 1
            noCoverage += 1
        case "CompileError": unviable += 1
        default: break
        }
        if let duration = mutant.duration { durations.append(duration) }
    }
}

struct Survivor {
    let project: String
    let operatorName: String
    let fingerprint: String
    let file: String
    let line: Int
    let original: String
    let replacement: String
}

struct Campaign {
    var cells: [String: [String: Cell]] = [:]  // project → operator → cell
    var survivors: [Survivor] = []

    var projects: [String] { cells.keys.sorted() }
    var operators: [String] { Set(cells.values.flatMap(\.keys)).sorted() }

    static func load(from directory: URL) throws -> Campaign {
        var campaign = Campaign()
        let reports = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasSuffix(".meta.json") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for url in reports {
            let project = url.deletingPathExtension().lastPathComponent
            let report = try JSONDecoder().decode(Report.self, from: Data(contentsOf: url))
            for (file, entry) in report.files.sorted(by: { $0.key < $1.key }) {
                for mutant in entry.mutants {
                    campaign.cells[project, default: [:]][mutant.mutatorName, default: Cell()].add(mutant)
                    if mutant.status == "Survived" {
                        campaign.survivors.append(
                            Survivor(
                                project: project, operatorName: mutant.mutatorName, fingerprint: mutant.fingerprint,
                                file: file, line: mutant.location.start.line,
                                original: mutant.originalText ?? "", replacement: mutant.replacement ?? ""
                            )
                        )
                    }
                }
            }
        }
        return campaign
    }
}

// MARK: - Equivalence reviews

struct Reviews {
    var reviewed: [String: Int] = [:]
    var equivalent: [String: Int] = [:]

    static func load(from path: String?) throws -> Reviews {
        var reviews = Reviews()
        guard let path, FileManager.default.fileExists(atPath: path) else { return reviews }
        let rows = try String(contentsOfFile: path, encoding: .utf8).components(separatedBy: "\n").dropFirst()
        for row in rows where !row.isEmpty {
            let fields = splitCSV(row)
            guard fields.count >= 7 else { continue }
            let operatorName = fields[1]
            switch fields[6] {
            case "equivalent":
                reviews.reviewed[operatorName, default: 0] += 1
                reviews.equivalent[operatorName, default: 0] += 1
            case "not-equivalent":
                reviews.reviewed[operatorName, default: 0] += 1
            default: break
            }
        }
        return reviews
    }

    func equivalentPercent(of operatorName: String) -> Double? {
        guard let reviewed = reviewed[operatorName], reviewed > 0 else { return nil }
        return Double(equivalent[operatorName] ?? 0) / Double(reviewed) * 100
    }
}

// MARK: - Tiers

enum Tier: String {
    case conservative, `default`, experimental

    static func assign(
        medianKillRate: Double?, unviable: Double?, equivalent: Double?, qualifiedProjects: Int
    ) -> String {
        guard qualifiedProjects >= 3, let medianKillRate, let unviable else {
            return "experimental (insufficient data)"
        }
        if medianKillRate < 40 || unviable > 15 { return "experimental" }
        guard let equivalent else { return "pending review" }
        if medianKillRate >= 70, unviable <= 5, equivalent <= 10 { return "conservative" }
        if equivalent <= 25 { return "default" }
        return "experimental"
    }
}

// MARK: - Aggregation

func aggregate(
    directory: URL, markdownPath: String, csvPath: String, equivalencePath: String?, minMutants: Int
) throws {
    let campaign = try Campaign.load(from: directory)
    let reviews = try Reviews.load(from: equivalencePath)
    var markdown: [String] = []
    var csv = ["project,operator,generated,detected,undetected,noCoverage,unviable,killRate,costPerMutantMs"]

    markdown.append(
        "| Operator | Tier by the criteria | Projects (≥ \(minMutants) mutants) | Median kill rate | Unviable "
            + "| Equivalent (reviewed) | Cost per mutant |"
    )
    markdown.append("|---|---|---|---|---|---|---|")
    for operatorName in campaign.operators {
        let cells = campaign.projects.compactMap { campaign.cells[$0]?[operatorName] }
        let qualified = cells.filter { $0.generated >= minMutants }
        let killRates = qualified.compactMap(\.killRate).sorted()
        let medianKillRate = median(of: killRates)
        let generated = cells.reduce(0) { $0 + $1.generated }
        let unviableCount = cells.reduce(0) { $0 + $1.unviable }
        let unviable = generated == 0 ? nil : Double(unviableCount) / Double(generated) * 100
        let durations = cells.flatMap(\.durations)
        let cost = durations.isEmpty ? nil : Double(durations.reduce(0, +)) / Double(durations.count)
        let equivalent = reviews.equivalentPercent(of: operatorName)
        let tier = Tier.assign(
            medianKillRate: medianKillRate, unviable: unviable, equivalent: equivalent,
            qualifiedProjects: qualified.count
        )
        let reviewedCount = reviews.reviewed[operatorName] ?? 0
        markdown.append(
            "| `\(operatorName)` | \(tier) | \(qualified.count) of \(cells.count) | \(percent(medianKillRate)) "
                + "| \(percent(unviable)) | \(percent(equivalent)) (\(reviewedCount)) | \(milliseconds(cost)) |"
        )
    }

    markdown.append("")
    markdown.append(
        "| Project | Operator | Generated | Detected | Survived | No coverage | Unviable | Kill rate "
            + "| Cost per mutant |"
    )
    markdown.append("|---|---|---|---|---|---|---|---|---|")
    for project in campaign.projects {
        for operatorName in campaign.operators {
            guard let cell = campaign.cells[project]?[operatorName] else { continue }
            let survived = cell.undetected - cell.noCoverage
            markdown.append(
                "| \(project) | `\(operatorName)` | \(cell.generated) | \(cell.detected) | \(survived) "
                    + "| \(cell.noCoverage) | \(cell.unviable) | \(percent(cell.killRate)) "
                    + "| \(milliseconds(cell.costPerMutant)) |"
            )
            csv.append(
                "\(project),\(operatorName),\(cell.generated),\(cell.detected),\(cell.undetected),"
                    + "\(cell.noCoverage),\(cell.unviable),\(number(cell.killRate)),\(number(cell.costPerMutant))"
            )
        }
    }

    try write(markdown.joined(separator: "\n") + "\n", to: markdownPath)
    try write(csv.joined(separator: "\n") + "\n", to: csvPath)
    print("Wrote \(markdownPath) and \(csvPath)")
}

func median(of sorted: [Double]) -> Double? {
    guard !sorted.isEmpty else { return nil }
    let middle = sorted.count / 2
    return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
}

func percent(_ value: Double?) -> String {
    value.map { String(format: "%.1f%%", $0) } ?? "—"
}

func milliseconds(_ value: Double?) -> String {
    value.map { String(format: "%.0f ms", $0) } ?? "—"
}

func number(_ value: Double?) -> String {
    value.map { String(format: "%.1f", $0) } ?? ""
}

// MARK: - Sampling survivors for review

struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}

func sample(directory: URL, csvPath: String, seed: UInt64, perCell: Int, force: Bool) throws {
    guard force || !FileManager.default.fileExists(atPath: csvPath) else {
        throw CampaignError("\(csvPath) exists and may hold reviews; pass --force to draw a new sample over it")
    }
    let campaign = try Campaign.load(from: directory)
    var generator = SplitMix64(state: seed)
    var rows = ["project,operator,fingerprint,file,line,mutation,verdict,note"]

    for project in campaign.projects {
        for operatorName in campaign.operators {
            let candidates = campaign.survivors.filter { $0.project == project && $0.operatorName == operatorName }
            for survivor in candidates.shuffled(using: &generator).prefix(perCell) {
                let mutation = "\(survivor.original) → \(survivor.replacement)"
                rows.append(
                    [
                        project, operatorName, survivor.fingerprint, survivor.file, String(survivor.line), mutation, "",
                        "",
                    ]
                    .map(csvField).joined(separator: ",")
                )
            }
        }
    }

    try write(rows.joined(separator: "\n") + "\n", to: csvPath)
    print("Wrote \(rows.count - 1) survivors to review to \(csvPath)")
}

// MARK: - Checking the aggregation against the fixture

func check(fixture: URL) throws {
    let output = FileManager.default.temporaryDirectory.appendingPathComponent(
        "operator-campaign-check-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: output) }
    try aggregate(
        directory: fixture, markdownPath: output.appendingPathComponent("results.md").path,
        csvPath: output.appendingPathComponent("results.csv").path,
        equivalencePath: fixture.appendingPathComponent("equivalence.csv").path, minMutants: 1
    )
    for (expected, actual) in [("expected.md", "results.md"), ("expected.csv", "results.csv")] {
        let expectedText = try String(contentsOf: fixture.appendingPathComponent(expected), encoding: .utf8)
        let actualText = try String(contentsOf: output.appendingPathComponent(actual), encoding: .utf8)
        guard expectedText == actualText else {
            throw CampaignError(
                "\(actual) differs from \(expected):\n--- expected\n\(expectedText)\n--- actual\n\(actualText)")
        }
    }
    print("check passed")
}

// MARK: - Running the corpus

func run(corpusPath: String, outDirectory: URL, toolPath: String) throws {
    let corpus = try JSONDecoder().decode([Project].self, from: Data(contentsOf: URL(fileURLWithPath: corpusPath)))
    try FileManager.default.createDirectory(at: outDirectory, withIntermediateDirectories: true)
    let toolVersion = try capture(toolPath, ["--version"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
    let swiftVersion = try capture("/usr/bin/swift", ["--version"]).output.components(separatedBy: "\n").first ?? ""
    let checkouts = FileManager.default.temporaryDirectory.appendingPathComponent(
        "operator-campaign-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: checkouts, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: checkouts) }

    for project in corpus {
        let path: String
        var sha = project.sha
        if project.repository == "." {
            path = FileManager.default.currentDirectoryPath
            sha = try capture("/usr/bin/git", ["rev-parse", "HEAD"]).output
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            let checkout = checkouts.appendingPathComponent(project.name)
            print("Cloning \(project.repository) at \(project.sha)")
            try check(capture("/usr/bin/git", ["clone", "--quiet", project.repository, checkout.path]), "git clone")
            try check(
                capture("/usr/bin/git", ["-C", checkout.path, "checkout", "--quiet", project.sha]), "git checkout")
            path = checkout.path
        }

        let report = outDirectory.appendingPathComponent("\(project.name).json").path
        let arguments =
            [path, "--no-cache", "--operator-tier", "experimental", "--output", report] + (project.arguments ?? [])
        print("Running \(project.name): \(toolPath) \(arguments.joined(separator: " "))")
        let started = Date()
        let result = try capture(toolPath, arguments)
        try write(result.output, to: outDirectory.appendingPathComponent("\(project.name).txt").path)

        let meta: [String: Any] = [
            "name": project.name, "repository": project.repository, "sha": sha,
            "tool": toolVersion, "swift": swiftVersion,
            "machine": "\(machineModel()), \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "date": ISO8601DateFormatter().string(from: started),
            "wallSeconds": Int(Date().timeIntervalSince(started)), "exitCode": Int(result.exitCode),
            "signaled": result.signaled,
        ]
        let data = try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: outDirectory.appendingPathComponent("\(project.name).meta.json"))
        let ending = result.signaled ? "signal" : "exit"
        print("  \(ending) \(result.exitCode) after \(Int(Date().timeIntervalSince(started))) s")
    }
}

func machineModel() -> String {
    (try? capture("/usr/sbin/sysctl", ["-n", "machdep.cpu.brand_string"]).output)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
}

// MARK: - Helpers

struct CampaignError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func capture(
    _ executable: String, _ arguments: [String]
) throws -> (exitCode: Int32, output: String, signaled: Bool) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (
        process.terminationStatus, String(decoding: data, as: UTF8.self),
        process.terminationReason == .uncaughtSignal
    )
}

func check(_ result: (exitCode: Int32, output: String, signaled: Bool), _ step: String) throws {
    guard result.exitCode == 0 else { throw CampaignError("\(step) failed:\n\(result.output)") }
}

func write(_ text: String, to path: String) throws {
    let url = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.write(to: url, atomically: true, encoding: .utf8)
}

func csvField(_ value: String) -> String {
    value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" })
        ? "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        : value
}

func splitCSV(_ row: String) -> [String] {
    var fields: [String] = []
    var field = ""
    var quoted = false
    var iterator = row.makeIterator()
    while let character = iterator.next() {
        switch (character, quoted) {
        case ("\"", true):
            quoted = false
        case ("\"", false):
            quoted = true
        case (",", false):
            fields.append(field)
            field = ""
        default:
            field.append(character)
        }
    }
    fields.append(field)
    return fields
}

func option(_ name: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

// MARK: - Entry point

setbuf(stdout, nil)

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first else { throw CampaignError("usage: campaign.swift run|aggregate|sample …") }

    switch command {
    case "run":
        guard arguments.count >= 3, let tool = option("--tool", in: arguments) else {
            throw CampaignError("usage: run <corpus.json> <out-dir> --tool <swift-mutation-testing>")
        }
        try run(corpusPath: arguments[1], outDirectory: URL(fileURLWithPath: arguments[2]), toolPath: tool)

    case "aggregate":
        guard
            arguments.count >= 2, let markdown = option("--markdown", in: arguments),
            let csv = option("--csv", in: arguments)
        else {
            throw CampaignError(
                "usage: aggregate <out-dir> --markdown <path> --csv <path> [--equivalence <csv>] [--min-mutants <n>]")
        }
        try aggregate(
            directory: URL(fileURLWithPath: arguments[1]), markdownPath: markdown, csvPath: csv,
            equivalencePath: option("--equivalence", in: arguments),
            minMutants: option("--min-mutants", in: arguments).flatMap(Int.init) ?? 10
        )

    case "sample":
        guard arguments.count >= 2, let csv = option("--csv", in: arguments) else {
            throw CampaignError("usage: sample <out-dir> --csv <path> [--seed <n>] [--per-cell <n>] [--force]")
        }
        try sample(
            directory: URL(fileURLWithPath: arguments[1]), csvPath: csv,
            seed: option("--seed", in: arguments).flatMap(UInt64.init) ?? 20_261_001,
            perCell: option("--per-cell", in: arguments).flatMap(Int.init) ?? 20,
            force: arguments.contains("--force")
        )

    case "check":
        let script = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        try check(fixture: script.appendingPathComponent("check"))

    default:
        throw CampaignError("unknown command '\(command)'")
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}

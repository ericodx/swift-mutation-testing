import Foundation

struct TestReference: Hashable, Sendable, Codable {
    let library: TestingFramework
    let id: String

    var module: String? {
        let prefix = id.prefix { $0 != "." && $0 != "/" }
        return prefix.count < id.count && id[id.index(id.startIndex, offsetBy: prefix.count)] == "."
            ? String(prefix) : nil
    }
}

struct TestCoverage: Sendable, Codable, Equatable {
    var sites: [String: [TestReference]] = [:]
    var outside: Set<String> = []

    var isEmpty: Bool { sites.isEmpty && outside.isEmpty }

    static func key(for mutant: MutantDescriptor) -> String? {
        mutant.functionBodyStart.map { key(suffix: SupportDeclarations.suffix(for: mutant.filePath), site: $0) }
    }

    static func key(suffix: String, site: Int) -> String {
        "\(suffix):\(site)"
    }

    enum Reach: Sendable, Equatable {
        case unreached
        case unknown
        case tests([TestReference])
    }

    func reach(of mutant: MutantDescriptor) -> Reach {
        guard let key = Self.key(for: mutant) else { return .unknown }
        if outside.contains(key) { return .unknown }
        guard let tests = sites[key] else { return .unreached }
        return .tests(tests)
    }

    mutating func merge(_ other: TestCoverage) {
        sites.merge(other.sites) { Array(Set($0 + $1)).sorted { $0.id < $1.id } }
        outside.formUnion(other.outside)
    }

    func resolvingTargets(identifiers: [String], targets: Set<String>) -> TestCoverage {
        var resolved = self
        for (key, tests) in sites {
            var seen: Set<TestReference> = []
            resolved.sites[key] = tests.flatMap { test -> [TestReference] in
                guard test.id.hasPrefix("/") else { return [test] }
                let path = test.id.dropFirst()
                var found: [String] = []
                for identifier in identifiers {
                    guard let slash = identifier.firstIndex(of: "/") else { continue }
                    let rest = identifier[identifier.index(after: slash)...]
                    let target = String(identifier[..<slash])
                    if path.isEmpty || rest == path || rest.hasPrefix(path + "/"), !found.contains(target) {
                        found.append(target)
                    }
                }
                if found.isEmpty, targets.count == 1, let only = targets.first { found = [only] }
                return found.map { TestReference(library: test.library, id: path.isEmpty ? $0 : $0 + test.id) }
            }.filter { seen.insert($0).inserted }
        }
        return resolved
    }
}

struct CoverageOutputParser: Sendable {
    init(xcodeTargets: [String: String]? = nil) {
        self.xcodeTargets = xcodeTargets
    }

    private let xcodeTargets: [String: String]?

    func parse(_ output: String) -> TestCoverage {
        var coverage = TestCoverage()
        var seen: [String: Set<TestReference>] = [:]
        var console = XcodeConsole()

        for raw in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = xcodeTargets == nil ? raw : Substring(raw.replacingOccurrences(of: Self.barrier, with: ""))
            if let key = record(in: line) {
                if let current = console.current {
                    if seen[key, default: []].insert(current).inserted {
                        coverage.sites[key, default: []].append(current)
                    }
                } else {
                    coverage.outside.insert(key)
                }
            } else if let boundary = boundary(in: line, console: &console) {
                console.current = boundary
            }
        }

        for key in coverage.outside where coverage.sites[key] == nil {
            coverage.sites[key] = []
        }
        return coverage
    }

    // MARK: - Private

    private struct XcodeConsole {
        var current: TestReference?
        var bundle: String?
        var suites: [String?] = []
    }

    private static let marker = SupportDeclarations.reachedMarker + " "
    private static let xctestStarted = "Test Case '-["
    private static let eventPrefix = "{\"kind\":\"event\""
    private static let barrier = "XCTestOutputBarrier"
    private static let bundleStarted = "Test Suite '"
    private static let suiteStarted = "◇ Suite "
    private static let testStarted = "◇ Test "
    private static let ended = ["✔ ", "✘ ", "⏭ "]
    private static let endings = [" passed after ", " failed after ", " skipped"]

    private func record(in line: Substring) -> String? {
        guard line.hasPrefix(Self.marker) else { return nil }
        return String(line.dropFirst(Self.marker.count))
    }

    private func boundary(in line: Substring, console: inout XcodeConsole) -> TestReference?? {
        if line.hasPrefix(Self.xctestStarted) {
            return xctestBoundary(in: line, console: console)
        }
        guard let xcodeTargets else {
            return line.hasPrefix(Self.eventPrefix) ? swiftTestingBoundary(in: line) : nil
        }
        return consoleBoundary(in: line, targets: xcodeTargets, console: &console)
    }

    private func xctestBoundary(in line: Substring, console: XcodeConsole) -> TestReference?? {
        let inner = line.dropFirst(Self.xctestStarted.count)
        guard let close = inner.range(of: "]'") else { return nil }
        let parts = inner[..<close.lowerBound].split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let remainder = inner[close.upperBound...]
        guard remainder.hasPrefix(" started") else { return .some(nil) }
        guard let targets = xcodeTargets else {
            return .some(TestReference(library: .xctest, id: "\(parts[0])/\(parts[1])"))
        }
        let qualified = parts[0].split(separator: ".", maxSplits: 1)
        let module = String(qualified[0])
        let target = targets[module] ?? console.bundle ?? module
        let type = qualified.count == 2 ? qualified[1] : qualified[0]
        return .some(TestReference(library: .xctest, id: "\(target)/\(type)/\(parts[1])"))
    }

    private func consoleBoundary(
        in line: Substring, targets: [String: String], console: inout XcodeConsole
    ) -> TestReference?? {
        if line.hasPrefix(Self.bundleStarted) {
            let name = line.dropFirst(Self.bundleStarted.count)
            if let close = name.range(of: ".xctest'") {
                let bundle = String(name[..<close.lowerBound])
                console.bundle = targets[bundle] ?? bundle
            }
            return nil
        }
        if line.hasPrefix(Self.suiteStarted) {
            console.suites.append(Self.name(of: line.dropFirst(Self.suiteStarted.count), function: false))
            return nil
        }
        if line.hasPrefix(Self.testStarted) {
            let name = line.dropFirst(Self.testStarted.count)
            guard name.hasSuffix(" started."), name != "run started." else { return nil }
            var path = console.suites.prefix { $0 != nil }.compactMap { $0 }
            if path.count == console.suites.count, let test = Self.name(of: name, function: true) {
                path.append(test)
            }
            let id = path.isEmpty ? (console.bundle ?? "/") : (console.bundle ?? "") + "/" + path.joined(separator: "/")
            return .some(TestReference(library: .swiftTesting, id: id))
        }
        guard let mark = Self.ended.first(where: { line.hasPrefix($0) }) else { return nil }
        let rest = line.dropFirst(mark.count)
        if rest.hasPrefix("Suite ") {
            if !console.suites.isEmpty { console.suites.removeLast() }
            return nil
        }
        guard rest.hasPrefix("Test "), Self.endings.contains(where: { rest.contains($0) }) else { return nil }
        return .some(nil)
    }

    private static func name(of text: Substring, function: Bool) -> String? {
        guard !text.hasPrefix("\"") else { return nil }
        let name = String(text.prefix { $0 != " " })
        guard !name.isEmpty, text.dropFirst(name.count) == " started.", name.hasSuffix(")") == function
        else { return nil }
        return name
    }

    private func swiftTestingBoundary(in line: Substring) -> TestReference?? {
        guard
            let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
            let payload = object["payload"] as? [String: Any],
            let kind = payload["kind"] as? String,
            let testID = payload["testID"] as? String,
            let test = Self.testID(withoutLocation: testID)
        else { return nil }

        switch kind {
        case "testStarted": return .some(TestReference(library: .swiftTesting, id: test))
        case "testEnded": return .some(nil)
        default: return nil
        }
    }

    static func testID(withoutLocation id: String) -> String? {
        let parts = id.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        if parts.count >= 3, parts.last.map({ $0.contains(".swift:") }) == true {
            return parts.dropLast().joined(separator: "/")
        }
        return id
    }
}

extension TestCoverage? {
    func reaching(_ mutant: MutantDescriptor) -> [TestReference]? {
        guard case .tests(let tests) = self?.reach(of: mutant), !tests.isEmpty else { return nil }
        return tests
    }
}

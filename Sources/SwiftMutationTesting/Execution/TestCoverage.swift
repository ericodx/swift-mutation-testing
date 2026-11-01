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
}

struct CoverageOutputParser: Sendable {
    func parse(_ output: String) -> TestCoverage {
        var coverage = TestCoverage()
        var current: TestReference?
        var seen: [String: Set<TestReference>] = [:]

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            if let key = record(in: line) {
                if let current {
                    if seen[key, default: []].insert(current).inserted {
                        coverage.sites[key, default: []].append(current)
                    }
                } else {
                    coverage.outside.insert(key)
                }
            } else if let boundary = boundary(in: line) {
                current = boundary
            }
        }

        for key in coverage.outside where coverage.sites[key] == nil {
            coverage.sites[key] = []
        }
        return coverage
    }

    // MARK: - Private

    private static let marker = SupportDeclarations.reachedMarker + " "
    private static let xctestStarted = "Test Case '-["
    private static let eventPrefix = "{\"kind\":\"event\""

    private func record(in line: Substring) -> String? {
        guard line.hasPrefix(Self.marker) else { return nil }
        return String(line.dropFirst(Self.marker.count))
    }

    private func boundary(in line: Substring) -> TestReference?? {
        if line.hasPrefix(Self.xctestStarted) {
            return xctestBoundary(in: line)
        }
        if line.hasPrefix(Self.eventPrefix) {
            return swiftTestingBoundary(in: line)
        }
        return nil
    }

    private func xctestBoundary(in line: Substring) -> TestReference?? {
        let inner = line.dropFirst(Self.xctestStarted.count)
        guard let close = inner.range(of: "]'") else { return nil }
        let parts = inner[..<close.lowerBound].split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let remainder = inner[close.upperBound...]
        if remainder.hasPrefix(" started") {
            return .some(TestReference(library: .xctest, id: "\(parts[0])/\(parts[1])"))
        }
        return .some(nil)
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

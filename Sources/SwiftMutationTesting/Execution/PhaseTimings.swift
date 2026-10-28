import Foundation

enum RunPhase: String, Codable, CaseIterable, Sendable {
    case discovery
    case sandbox
    case schemaBuild
    case schemaNarrowing
    case unmutatedBuildCheck
    case workers
    case baseline
    case unmutatedSuiteCheck
    case mutants
    case stragglers
    case unactivatedKills
    case fallbackBuilds
    case warmSandboxes
    case incompatible
    case teardown

    var label: String {
        switch self {
        case .discovery: "Discovery"
        case .sandbox: "Sandbox"
        case .schemaBuild: "Schema build"
        case .schemaNarrowing: "Schema narrowing"
        case .unmutatedBuildCheck: "Unmutated build check"
        case .workers: "Workers"
        case .baseline: "Baseline"
        case .unmutatedSuiteCheck: "Unmutated suite check"
        case .mutants: "Mutants"
        case .stragglers: "Stragglers"
        case .unactivatedKills: "Kills without activation"
        case .fallbackBuilds: "Fallback builds"
        case .warmSandboxes: "Warm sandboxes"
        case .incompatible: "Incompatible mutants"
        case .teardown: "Teardown"
        }
    }
}

struct PhaseTiming: Codable, Equatable, Sendable {
    let phase: RunPhase
    let start: Date
    let duration: Double
}

actor PhaseTimings {
    private(set) var entries: [PhaseTiming] = []

    func record(_ phase: RunPhase, start: Date, end: Date = Date()) {
        entries.append(PhaseTiming(phase: phase, start: start, duration: end.timeIntervalSince(start)))
    }

    static func measure<Value: Sendable>(
        _ phase: RunPhase,
        in timings: PhaseTimings?,
        _ work: () async throws -> Value
    ) async rethrows -> Value {
        let start = Date()
        do {
            let value = try await work()
            await timings?.record(phase, start: start)
            return value
        } catch {
            await timings?.record(phase, start: start)
            throw error
        }
    }
}

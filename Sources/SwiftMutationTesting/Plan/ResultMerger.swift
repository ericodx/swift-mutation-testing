import Foundation

struct ResultMerger: Sendable {
    struct Merged: Sendable {
        let results: [ExecutionResult]
        let totalDuration: Double
        let planSha256: String
    }

    private struct Verdict {
        let path: String
        let mutant: MutationReportMutant
    }

    func merge(resultPaths: [String], plan: Plan, projectPath: String) throws -> Merged {
        let planSha256 = try PlanStore.sha256(of: plan)
        var verdicts: [String: Verdict] = [:]

        for path in resultPaths {
            let payload = try read(path)
            guard let identity = payload.config else { throw MergeError.noIdentity(path: path) }
            guard identity.planSha256 == planSha256 else { throw MergeError.differentPlan(path: path) }

            for mutant in payload.files.values.flatMap(\.mutants) {
                if let earlier = verdicts[mutant.fingerprint] {
                    throw MergeError.duplicate(fingerprint: mutant.fingerprint, paths: [earlier.path, path])
                }
                verdicts[mutant.fingerprint] = Verdict(path: path, mutant: mutant)
            }
        }

        var found: [(index: Int, mutant: Plan.Mutant, verdict: Verdict)] = []
        var missing: [Plan.Mutant] = []
        for (index, mutant) in plan.mutants.enumerated() {
            if let verdict = verdicts[mutant.fingerprint] {
                found.append((index, mutant, verdict))
            } else {
                missing.append(mutant)
            }
        }
        guard missing.isEmpty else {
            throw MergeError.missing(
                count: missing.count, sample: missing.prefix(5).map { "\($0.fingerprint) (\($0.file):\($0.line))" }
            )
        }

        let fileHashes = PlanMaterializer.fileHashes(of: plan)
        let results = try found.map { index, mutant, verdict in
            ExecutionResult(
                descriptor: PlanMaterializer.descriptor(
                    of: mutant, at: index, fileHashes: fileHashes, projectPath: projectPath),
                status: try Self.status(of: verdict.mutant, in: verdict.path),
                testDuration: Double(verdict.mutant.duration ?? 0) / 1000,
                activated: verdict.mutant.activated
            )
        }

        return Merged(
            results: results, totalDuration: results.reduce(0) { $0 + $1.testDuration }, planSha256: planSha256
        )
    }

    private func read(_ path: String) throws -> MutationReportPayload {
        guard
            let data = FileManager.default.contents(atPath: path),
            let payload = try? JSONDecoder().decode(MutationReportPayload.self, from: data)
        else { throw MergeError.unreadableResult(path: path) }
        return payload
    }

    private static func status(of mutant: MutationReportMutant, in path: String) throws -> ExecutionStatus {
        switch mutant.status {
        case "Killed":
            if let killer = mutant.killedBy?.first { return .killed(by: killer) }
            return .killedByCrash
        case "Survived": return .survived
        case "NoCoverage": return .noCoverage
        case "Timeout": return .timeout
        case "CompileError": return .unviable
        default: throw MergeError.unknownStatus(path: path, status: mutant.status)
        }
    }
}

struct Shard: Sendable, Equatable, CustomStringConvertible {
    let index: Int
    let count: Int

    init?(parsing raw: String) {
        let parts = raw.split(separator: "/", omittingEmptySubsequences: false)
        guard
            parts.count == 2, let index = Int(parts[0]), let count = Int(parts[1]),
            count >= 1, index >= 1, index <= count
        else { return nil }
        self.index = index
        self.count = count
    }

    init(index: Int, count: Int) {
        self.index = index
        self.count = count
    }

    var description: String { "\(index)/\(count)" }
}

enum ShardSelector {
    static func files(of plan: Plan, in shard: Shard) -> [String] {
        var countByFile: [String: Int] = [:]
        for mutant in plan.mutants {
            countByFile[mutant.file, default: 0] += 1
        }

        var load = Array(repeating: 0, count: shard.count)
        var assigned: [String] = []
        for (file, count) in countByFile.sorted(by: { $0.key < $1.key }) {
            var lightest = 0
            for index in load.indices where load[index] < load[lightest] {
                lightest = index
            }
            load[lightest] += count
            if lightest == shard.index - 1 {
                assigned.append(file)
            }
        }
        return assigned
    }

    static func mutants(of plan: Plan, in shard: Shard) -> [Plan.Mutant] {
        let files = Set(files(of: plan, in: shard))
        return plan.mutants.filter { files.contains($0.file) }
    }
}

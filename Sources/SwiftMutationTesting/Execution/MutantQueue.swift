import Foundation

actor MutantQueue {
    private var remaining: ArraySlice<IncompatibleMutantExecutor.WarmMutant>

    init(_ mutants: [IncompatibleMutantExecutor.WarmMutant]) {
        remaining = mutants[...]
    }

    func next() -> IncompatibleMutantExecutor.WarmMutant? {
        remaining.popFirst()
    }

    func drain() -> [IncompatibleMutantExecutor.WarmMutant] {
        defer { remaining = [] }
        return Array(remaining)
    }
}

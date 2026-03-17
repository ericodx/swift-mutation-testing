actor MutationCounter {
    init(total: Int) {
        self.total = total
    }

    nonisolated let total: Int
    private(set) var completed: Int = 0

    func increment() -> Int {
        completed += 1
        return completed
    }
}

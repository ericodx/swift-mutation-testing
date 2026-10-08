struct FunctionBodyScopes: Sendable {
    let scopes: [FunctionBodyScope]

    init(scopes: [FunctionBodyScope]) {
        self.scopes = scopes

        let sorted = scopes.sorted {
            ($0.bodyStartOffset, -$0.bodyEndOffset) < ($1.bodyStartOffset, -$1.bodyEndOffset)
        }
        var parents: [Int?] = []
        var open: [Int] = []
        for (index, scope) in sorted.enumerated() {
            while let last = open.last, sorted[last].bodyEndOffset <= scope.bodyStartOffset {
                open.removeLast()
            }
            parents.append(open.last)
            open.append(index)
        }
        byStart = sorted
        parentIndices = parents
    }

    func isSchematizable(utf8Offset: Int) -> Bool {
        innermostScope(containing: utf8Offset) != nil
    }

    func innermostScope(containing utf8Offset: Int) -> FunctionBodyScope? {
        var low = 0
        var high = byStart.count
        while low < high {
            let middle = (low + high) / 2
            if byStart[middle].bodyStartOffset <= utf8Offset { low = middle + 1 } else { high = middle }
        }

        var candidate = low > 0 ? low - 1 : nil
        while let index = candidate {
            if utf8Offset < byStart[index].bodyEndOffset { return byStart[index] }
            candidate = parentIndices[index]
        }
        return nil
    }

    // MARK: - Private

    private let byStart: [FunctionBodyScope]
    private let parentIndices: [Int?]
}

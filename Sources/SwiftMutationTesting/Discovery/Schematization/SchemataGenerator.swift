import SwiftSyntax

struct SchemataGenerator: Sendable {
    private typealias Entry = (index: Int, point: MutationPoint)
    private typealias ScopeGroup = (scope: FunctionBodyScope, mutations: [Entry])

    func generate(
        source: ParsedSource, mutations: [(index: Int, point: MutationPoint)], importStyle: ImportStyle = .implicit
    ) -> SchemaGeneration {
        var (groups, discarded) = groupByScope(mutations, in: source.functionScopes)

        var bytes = Array(source.file.content.utf8)
        var edits = Edits()

        for group in groups {
            let body = schemaBody(for: group, in: bytes, edits: edits, path: source.file.path)
            discarded += body.discarded
            guard let switchBody = body.switchBody else { continue }

            let scope = group.scope
            let start = edits.current(scope.bodyStartOffset)
            let end = edits.current(scope.bodyEndOffset)
            guard UTF8Splice.isRange(from: start, to: end, in: bytes) else { continue }

            bytes.replaceSubrange(start ..< end, with: switchBody.utf8)
            edits.record(
                start: scope.bodyStartOffset,
                delta: switchBody.utf8.count - (scope.bodyEndOffset - scope.bodyStartOffset)
            )
        }

        guard !edits.isEmpty else {
            return SchemaGeneration(content: source.file.content, discarded: discarded)
        }

        let content = String(decoding: bytes, as: UTF8.self)

        return SchemaGeneration(
            content: SupportDeclarations.appended(
                to: content, path: source.file.path, syntax: source.syntax, style: importStyle
            ),
            discarded: discarded
        )
    }

    private func groupByScope(
        _ mutations: [Entry], in scopes: FunctionBodyScopes
    ) -> (groups: [ScopeGroup], discarded: [MutationPoint]) {
        var groupedByScope: [Int: ScopeGroup] = [:]
        var discarded: [MutationPoint] = []

        for entry in mutations {
            guard let scope = scopes.innermostScope(containing: entry.point.utf8Offset) else {
                discarded.append(entry.point)
                continue
            }

            groupedByScope[scope.bodyStartOffset, default: (scope: scope, mutations: [])].mutations.append(entry)
        }

        let groups = groupedByScope.values.sorted { $0.scope.bodyStartOffset > $1.scope.bodyStartOffset }
        return (groups, discarded)
    }

    private func schemaBody(
        for group: ScopeGroup, in bytes: [UInt8], edits: Edits, path: String
    ) -> (switchBody: String?, discarded: [MutationPoint]) {
        let scope = group.scope
        let statementsStart = edits.current(scope.statementsStartOffset)
        let statementsEnd = edits.current(scope.statementsEndOffset)

        guard
            UTF8Splice.isRange(from: statementsStart, to: statementsEnd, in: bytes),
            let originalStatements = String(bytes: bytes[statementsStart ..< statementsEnd], encoding: .utf8)
        else {
            return (nil, group.mutations.map(\.point))
        }
        let statementBytes = Array(bytes[statementsStart ..< statementsEnd])

        var cases: [(id: String, statements: String)] = []
        var discarded: [MutationPoint] = []

        for entry in group.mutations.sorted(by: { $0.index < $1.index }) {
            guard
                let mutated = apply(
                    entry.point,
                    to: statementBytes,
                    at: edits.current(entry.point.utf8Offset) - statementsStart
                )
            else {
                discarded.append(entry.point)
                continue
            }
            cases.append((id: MutantID.make(index: entry.index), statements: mutated))
        }

        guard !cases.isEmpty else { return (nil, discarded) }

        let switchBody = buildSwitchBody(
            cases: cases, defaultStatements: originalStatements, shape: scope.shape, path: path
        )
        return (switchBody, discarded)
    }

    struct Edits {
        private var starts: [Int] = []
        private var runningTotals: [Int] = []

        var isEmpty: Bool { starts.isEmpty }

        func current(_ originalOffset: Int) -> Int {
            var low = 0
            var high = starts.count
            while low < high {
                let middle = (low + high) / 2
                if starts[middle] < originalOffset { high = middle } else { low = middle + 1 }
            }
            guard low < starts.count else { return originalOffset }
            let before = low == 0 ? 0 : runningTotals[low - 1]
            return originalOffset + (runningTotals[runningTotals.count - 1] - before)
        }

        mutating func record(start: Int, delta: Int) {
            starts.append(start)
            runningTotals.append((runningTotals.last ?? 0) + delta)
        }
    }

    private func apply(_ mutation: MutationPoint, to statements: [UInt8], at relativeOffset: Int) -> String? {
        UTF8Splice.replacing(
            from: relativeOffset,
            to: relativeOffset + mutation.originalText.utf8.count,
            in: statements,
            with: mutation.mutatedText
        )
    }

    private func buildSwitchBody(
        cases: [(id: String, statements: String)],
        defaultStatements: String,
        shape: FunctionBodyShape,
        path: String
    ) -> String {
        var result = "{\n"
        result += "switch \(SupportDeclarations.identifier(for: path)) {\n"

        for (id, statements) in cases {
            result += "case \"\(id)\":\n\(caseBody(statements, shape: shape, path: path))\n"
        }

        result += "default:\n\(defaultBody(defaultStatements, shape: shape))\n"
        result += "}\n}"

        return result
    }

    private func caseBody(_ statements: String, shape: FunctionBodyShape, path: String) -> String {
        let activation = SupportDeclarations.activationCall(for: path)
        let isBlank = statements.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        switch shape {
        case .expression where !isBlank:
            return "(\(activation), \(statements)).1"
        case .conditional(returnsValue: true):
            return "let _ = \(activation)\nreturn \(statements)"
        case .expression, .conditional, .statements:
            return "let _ = \(activation)\n\(statements)"
        }
    }

    private func defaultBody(_ statements: String, shape: FunctionBodyShape) -> String {
        shape == .conditional(returnsValue: true) ? "return \(statements)" : statements
    }
}

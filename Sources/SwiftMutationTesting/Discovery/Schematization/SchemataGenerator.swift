import SwiftSyntax

struct SchemataGenerator: Sendable {
    private typealias Entry = (index: Int, point: MutationPoint)
    private typealias ScopeGroup = (scope: FunctionBodyScope, mutations: [Entry])

    func generate(
        source: ParsedSource, mutations: [(index: Int, point: MutationPoint)], importStyle: ImportStyle = .implicit
    ) -> SchemaGeneration {
        var (groups, discarded) = groupByScope(mutations, in: source.functionScopes)

        var content = source.file.content
        var edits = Edits()

        for group in groups {
            let body = schemaBody(for: group, in: content, edits: edits, path: source.file.path)
            discarded += body.discarded
            guard let switchBody = body.switchBody else { continue }

            let scope = group.scope
            content =
                UTF8Splice.replacing(
                    from: edits.current(scope.bodyStartOffset),
                    to: edits.current(scope.bodyEndOffset),
                    in: content,
                    with: switchBody
                ) ?? content
            edits.record(
                start: scope.bodyStartOffset,
                delta: switchBody.utf8.count - (scope.bodyEndOffset - scope.bodyStartOffset)
            )
        }

        guard content != source.file.content else {
            return SchemaGeneration(content: content, discarded: discarded)
        }

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
        for group: ScopeGroup, in content: String, edits: Edits, path: String
    ) -> (switchBody: String?, discarded: [MutationPoint]) {
        let scope = group.scope
        let statementsStart = edits.current(scope.statementsStartOffset)

        guard
            let originalStatements = UTF8Splice.substring(
                of: content, from: statementsStart, to: edits.current(scope.statementsEndOffset)
            )
        else {
            return (nil, group.mutations.map(\.point))
        }

        var cases: [(id: String, statements: String)] = []
        var discarded: [MutationPoint] = []

        for entry in group.mutations.sorted(by: { $0.index < $1.index }) {
            guard
                let mutated = apply(
                    entry.point,
                    to: originalStatements,
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

    private struct Edits {
        private var deltas: [(start: Int, delta: Int)] = []

        func current(_ originalOffset: Int) -> Int {
            deltas.filter { $0.start < originalOffset }.reduce(originalOffset) { $0 + $1.delta }
        }

        mutating func record(start: Int, delta: Int) {
            deltas.append((start: start, delta: delta))
        }
    }

    private func apply(_ mutation: MutationPoint, to statementsText: String, at relativeOffset: Int) -> String? {
        UTF8Splice.replacing(
            from: relativeOffset,
            to: relativeOffset + mutation.originalText.utf8.count,
            in: statementsText,
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

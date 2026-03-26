struct SchemataGenerator: Sendable {
    func generate(source: ParsedSource, mutations: [(index: Int, point: MutationPoint)]) -> String {
        let visitor = TypeScopeVisitor()
        visitor.walk(source.syntax)

        var groupedByScope: [Int: (scope: FunctionBodyScope, mutations: [(index: Int, point: MutationPoint)])] = [:]

        for entry in mutations {
            guard let scope = visitor.innermostScope(containing: entry.point.utf8Offset) else {
                continue
            }

            groupedByScope[scope.bodyStartOffset, default: (scope: scope, mutations: [])].mutations
                .append(entry)
        }

        let sortedGroups = groupedByScope.values.sorted {
            $0.scope.bodyStartOffset > $1.scope.bodyStartOffset
        }

        var content = source.file.content

        for group in sortedGroups {
            let scope = group.scope

            guard
                let originalStatements = extract(
                    from: source.file.content,
                    start: scope.statementsStartOffset,
                    end: scope.statementsEndOffset
                )
            else { continue }

            let sortedMutations = group.mutations.sorted { $0.index < $1.index }
            var cases: [(id: String, statements: String)] = []

            for entry in sortedMutations {
                let mutated = apply(
                    entry.point,
                    to: originalStatements,
                    startOffset: scope.statementsStartOffset
                )
                cases.append((id: mutantID(entry.index), statements: mutated))
            }

            let switchBody = buildSwitchBody(cases: cases, defaultStatements: originalStatements)
            content = replaceRange(
                in: content,
                start: scope.bodyStartOffset,
                end: scope.bodyEndOffset,
                with: switchBody
            )
        }

        return content
    }

    private func mutantID(_ index: Int) -> String {
        "swift-mutation-testing_\(index)"
    }

    private func extract(from content: String, start: Int, end: Int) -> String? {
        guard let data = content.data(using: .utf8),
            start >= 0, end <= data.count, start <= end
        else { return nil }
        return String(data: data.subdata(in: start ..< end), encoding: .utf8)
    }

    private func apply(_ mutation: MutationPoint, to statementsText: String, startOffset: Int) -> String {
        guard let statementsData = statementsText.data(using: .utf8),
            let originalData = mutation.originalText.data(using: .utf8),
            let mutatedData = mutation.mutatedText.data(using: .utf8)
        else { return statementsText }

        let relativeOffset = mutation.utf8Offset - startOffset

        guard relativeOffset >= 0, relativeOffset + originalData.count <= statementsData.count
        else { return statementsText }

        var result = statementsData
        result.replaceSubrange(relativeOffset ..< relativeOffset + originalData.count, with: mutatedData)
        return String(data: result, encoding: .utf8) ?? statementsText
    }

    private func buildSwitchBody(
        cases: [(id: String, statements: String)],
        defaultStatements: String
    ) -> String {
        var result = "{\n"
        result += "switch __swiftMutationTestingID {\n"

        for (id, statements) in cases {
            result += "case \"\(id)\":\n\(statements)\n"
        }

        result += "default:\n\(defaultStatements)\n"
        result += "}\n}"

        return result
    }

    private func replaceRange(
        in content: String, start: Int, end: Int, with replacement: String
    )
        -> String
    {
        guard let contentData = content.data(using: .utf8),
            let replacementData = replacement.data(using: .utf8),
            start >= 0, end <= contentData.count
        else { return content }

        var result = contentData
        result.replaceSubrange(start ..< end, with: replacementData)
        return String(data: result, encoding: .utf8) ?? content
    }
}

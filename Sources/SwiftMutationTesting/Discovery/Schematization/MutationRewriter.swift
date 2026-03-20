struct MutationRewriter {
    func rewrite(source: String, applying mutation: MutationPoint) -> String {
        guard let sourceData = source.data(using: .utf8),
            let originalData = mutation.originalText.data(using: .utf8),
            let mutatedData = mutation.mutatedText.data(using: .utf8)
        else { return source }

        let offset = mutation.utf8Offset

        guard offset >= 0, offset + originalData.count <= sourceData.count
        else { return source }

        var result = sourceData
        result.replaceSubrange(offset ..< offset + originalData.count, with: mutatedData)
        return String(data: result, encoding: .utf8) ?? source
    }
}

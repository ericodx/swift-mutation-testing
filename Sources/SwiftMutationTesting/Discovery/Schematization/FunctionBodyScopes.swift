struct FunctionBodyScopes: Sendable {
    let scopes: [FunctionBodyScope]

    func isSchematizable(utf8Offset: Int) -> Bool {
        scopes.contains {
            $0.bodyStartOffset <= utf8Offset && utf8Offset < $0.bodyEndOffset
        }
    }

    func innermostScope(containing utf8Offset: Int) -> FunctionBodyScope? {
        scopes
            .filter { $0.bodyStartOffset <= utf8Offset && utf8Offset < $0.bodyEndOffset }
            .min { ($0.bodyEndOffset - $0.bodyStartOffset) < ($1.bodyEndOffset - $1.bodyStartOffset) }
    }
}

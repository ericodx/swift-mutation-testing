import SwiftSyntax

class MutationSyntaxVisitor: SyntaxVisitor {
    required init(source: ParsedSource) {
        filePath = source.file.path
        locationConverter = source.locationConverter
        super.init(viewMode: .sourceAccurate)
    }

    var mutations: [MutationPoint] = []
    let filePath: String
    let locationConverter: SourceLocationConverter

    override func visit(_ node: IfConfigClauseSyntax) -> SyntaxVisitorContinueKind {
        if let elements = node.elements {
            walk(elements)
        }
        return .skipChildren
    }
}

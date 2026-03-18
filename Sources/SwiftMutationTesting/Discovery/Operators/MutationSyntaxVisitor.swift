import SwiftSyntax

class MutationSyntaxVisitor: SyntaxVisitor {
    init(source: ParsedSource) {
        filePath = source.file.path
        locationConverter = SourceLocationConverter(fileName: source.file.path, tree: source.syntax)
        super.init(viewMode: .sourceAccurate)
    }

    var mutations: [MutationPoint] = []
    let filePath: String
    let locationConverter: SourceLocationConverter
}

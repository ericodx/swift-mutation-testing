import SwiftSyntax

struct ParsedSource: Sendable {
    let file: SourceFile
    let syntax: SourceFileSyntax
}

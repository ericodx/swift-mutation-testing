import SwiftParser
import SwiftSyntax

@testable import SwiftMutationTesting

func makeParsedSource(_ code: String, path: String = "test.swift") -> ParsedSource {
    ParsedSource(
        file: SourceFile(path: path, content: code),
        syntax: Parser.parse(source: code)
    )
}

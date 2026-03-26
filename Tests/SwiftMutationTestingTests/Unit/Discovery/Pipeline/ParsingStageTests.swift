import Testing

@testable import SwiftMutationTesting

@Suite("ParsingStage")
struct ParsingStageTests {
    private let stage = ParsingStage()

    @Test("Given valid swift code, when run, then returns ParsedSource with correct file")
    func parsesValidCode() async {
        let file = SourceFile(path: "test.swift", content: "let x = 1")
        let result = await stage.run(sourceFiles: [file])
        #expect(result.count == 1)
        #expect(result[0].file.path == "test.swift")
        #expect(result[0].file.content == "let x = 1")
    }

    @Test("Given multiple files, when run, then returns one ParsedSource per file")
    func parsesMultipleFiles() async {
        let files = [
            SourceFile(path: "a.swift", content: "let a = 1"),
            SourceFile(path: "b.swift", content: "let b = 2"),
            SourceFile(path: "c.swift", content: "let c = 3"),
        ]
        let result = await stage.run(sourceFiles: files)
        #expect(result.count == 3)
    }

    @Test("Given empty file list, when run, then returns empty array")
    func parsesEmptyList() async {
        let result = await stage.run(sourceFiles: [])
        #expect(result.isEmpty)
    }

    @Test("Given syntactically invalid code, when run, then still returns a ParsedSource")
    func parsesInvalidCode() async {
        let file = SourceFile(path: "broken.swift", content: "func { invalid ??? }")
        let result = await stage.run(sourceFiles: [file])
        #expect(result.count == 1)
        #expect(result[0].file.path == "broken.swift")
    }
}

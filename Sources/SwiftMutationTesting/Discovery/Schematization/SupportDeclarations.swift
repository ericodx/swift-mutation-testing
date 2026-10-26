import CryptoKit
import Foundation
import SwiftSyntax

enum SupportDeclarations {
    static func suffix(for path: String) -> String {
        SHA256.hash(data: Data(path.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    static let identifierPrefix = "__swiftMutationTestingID_"

    static func identifier(for path: String) -> String {
        "\(identifierPrefix)\(suffix(for: path))"
    }

    static func activationCall(for path: String) -> String {
        "__SwiftMutationTesting_\(suffix(for: path)).activated()"
    }

    static func activatingCall(for path: String) -> String {
        "__SwiftMutationTesting_\(suffix(for: path)).activating"
    }

    static func importLine(_ style: ImportStyle) -> String {
        switch style {
        case .implicit: "import Foundation"
        case .explicit: "internal import Foundation"
        }
    }

    static func appended(to content: String, path: String, syntax: SourceFileSyntax, style: ImportStyle) -> String {
        var support = perFile(for: path)
        if !ImportStyle.importsFoundation(syntax) {
            support = importLine(style) + "\n\n" + support
        }
        return content + "\n\n" + support + "\n"
    }

    static func perFile(for path: String) -> String {
        let suffix = suffix(for: path)
        return """
            @usableFromInline
            internal enum __SwiftMutationTesting_\(suffix) {
                @usableFromInline nonisolated static let id: String =
                    ProcessInfo.processInfo.environment["__SWIFT_MUTATION_TESTING_ACTIVE"] ?? ""
                nonisolated(unsafe) static var activationRecorded = false

                @usableFromInline nonisolated static func activated() {
                    guard
                        !activationRecorded,
                        let path = ProcessInfo.processInfo.environment["__SWIFT_MUTATION_TESTING_ACTIVATION_FILE"]
                    else { return }
                    activationRecorded = true
                    FileManager.default.createFile(atPath: path, contents: nil)
                }

                @discardableResult @usableFromInline nonisolated static func activating<T>(_ value: T) -> T {
                    activated()
                    return value
                }
            }

            @usableFromInline nonisolated internal var __swiftMutationTestingID_\(suffix): String {
                __SwiftMutationTesting_\(suffix).id
            }
            """
    }
}

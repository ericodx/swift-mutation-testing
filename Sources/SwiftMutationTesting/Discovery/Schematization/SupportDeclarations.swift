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

    static let coverageEnvironmentVariable = "__SWIFT_MUTATION_TESTING_COVERAGE_FILE"
    static let coverageRedirectVariable = "__SWIFT_MUTATION_TESTING_COVERAGE_REDIRECT"
    static let reachedMarker = "__swiftMutationTestingReached"

    static func reachedCall(for path: String, site: Int) -> String {
        "__SwiftMutationTesting_\(suffix(for: path)).reached(\(site))"
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
            \(coverageSupport(suffix: suffix))
            }

            @usableFromInline nonisolated internal var __swiftMutationTestingID_\(suffix): String {
                __SwiftMutationTesting_\(suffix).id
            }
            """
    }

    private static func coverageSupport(suffix: String) -> String {
        """

                nonisolated static let coverageDescriptor: Int32 = {
                    let environment = ProcessInfo.processInfo.environment
                    guard let path = environment["\(coverageEnvironmentVariable)"] else { return -1 }
                    let descriptor = open(path, O_WRONLY | O_APPEND)
                    if descriptor >= 0, environment["\(coverageRedirectVariable)"] != nil { dup2(descriptor, 2) }
                    return descriptor
                }()
                nonisolated(unsafe) static var reachedSites: Set<Int> = []
                nonisolated(unsafe) static var reachedSize: off_t = -1
                nonisolated static let reachedLock = NSLock()

                nonisolated static func coverageSize() -> off_t {
                    var status = stat()
                    return fstat(coverageDescriptor, &status) == 0 ? status.st_size : -1
                }

                @usableFromInline nonisolated static func reached(_ site: Int) {
                    guard coverageDescriptor >= 0 else { return }
                    reachedLock.lock()
                    defer { reachedLock.unlock() }
                    if coverageSize() != reachedSize { reachedSites.removeAll(keepingCapacity: true) }
                    if reachedSites.insert(site).inserted {
                        let line = "\(reachedMarker) \(suffix):\\(site)\\n"
                        line.withCString { _ = write(coverageDescriptor, $0, strlen($0)) }
                    }
                    reachedSize = coverageSize()
                }
        """
    }
}

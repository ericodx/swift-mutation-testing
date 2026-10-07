import Foundation
import Synchronization

@testable import SwiftMutationTesting

final class SimulatorCloneFailureMock: ProcessLaunching, Sendable {

    init(failingCloneIndices: Set<Int> = [], bootFails: Bool = false) {
        self.failingCloneIndices = failingCloneIndices
        self.bootFails = bootFails
    }

    var deletedUDIDs: [String] {
        deleted.withLock { $0.sorted() }
    }

    func launch(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        timeout: Double
    ) async throws -> Int32 {
        if arguments.contains("boot"), bootFails {
            throw SimulatorError.bootTimeout(udid: arguments.last ?? "")
        }
        if arguments.contains("delete"), let udid = arguments.last {
            deleted.withLock { $0.append(udid) }
        }
        return 0
    }

    func launchCapturing(
        _ request: ProcessRequest
    ) async throws -> (exitCode: Int32, output: String) {
        request.recordActivation()
        guard
            request.arguments.contains("clone"),
            let name = request.arguments.last,
            let index = name.split(separator: "-").last.flatMap({ Int($0) })
        else {
            return (0, "")
        }
        if failingCloneIndices.contains(index) {
            return (1, "")
        }
        return (0, "CLONE-\(index)\n")
    }

    // MARK: - Private

    private let failingCloneIndices: Set<Int>
    private let bootFails: Bool
    private let deleted = Mutex<[String]>([])
}

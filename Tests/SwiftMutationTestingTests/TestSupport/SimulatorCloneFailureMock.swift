import Foundation
import Synchronization

@testable import SwiftMutationTesting

final class SimulatorCloneFailureMock: ProcessLaunching, Sendable {

    init(
        failingCloneIndices: Set<Int> = [], bootFails: Bool = false, listOutput: String = "",
        dataKilobytes: Int64? = nil
    ) {
        self.failingCloneIndices = failingCloneIndices
        self.bootFails = bootFails
        self.listOutput = listOutput
        self.dataKilobytes = dataKilobytes
    }

    var deletedUDIDs: [String] {
        deleted.withLock { $0.sorted() }
    }

    var cloneTimeouts: [Double] {
        timeouts.withLock { $0 }
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
        if request.arguments.contains("list") {
            return (0, listOutput)
        }
        if request.executableURL.lastPathComponent == "du" {
            guard let dataKilobytes else { return (1, "") }
            return (0, "\(dataKilobytes)\t\(request.arguments.last ?? "")\n")
        }
        guard
            request.arguments.contains("clone"),
            let name = request.arguments.last,
            let index = name.split(separator: "-").last.flatMap({ Int($0) })
        else {
            return (0, "")
        }
        timeouts.withLock { $0.append(request.timeout) }
        if failingCloneIndices.contains(index) {
            return (1, "")
        }
        return (0, "CLONE-\(index)\n")
    }

    // MARK: - Private

    private let failingCloneIndices: Set<Int>
    private let bootFails: Bool
    private let listOutput: String
    private let dataKilobytes: Int64?
    private let deleted = Mutex<[String]>([])
    private let timeouts = Mutex<[Double]>([])
}

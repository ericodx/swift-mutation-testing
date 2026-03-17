@testable import SwiftMutationTesting

actor MockProgressReporter: ProgressReporter {
    private(set) var events: [RunnerEvent] = []

    func report(_ event: RunnerEvent) async {
        events.append(event)
    }
}

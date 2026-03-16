protocol ProgressReporter: Sendable {
    func report(_ event: RunnerEvent) async
}

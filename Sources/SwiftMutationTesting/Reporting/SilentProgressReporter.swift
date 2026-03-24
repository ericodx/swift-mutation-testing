struct SilentProgressReporter: Sendable, ProgressReporter {
    func report(_ event: RunnerEvent) async {}
}

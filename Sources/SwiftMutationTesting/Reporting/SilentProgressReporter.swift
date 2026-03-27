struct SilentProgressReporter: Sendable, ProgressReporter {
    func report(_ _: RunnerEvent) async {}
}

struct SilentProgressReporter: ProgressReporter {
    func report(_ event: RunnerEvent) async {}
}

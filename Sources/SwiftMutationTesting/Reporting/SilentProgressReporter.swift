struct SilentProgressReporter: Sendable, ProgressReporter {
    func report(_ _: RunnerEvent) async {
        // Intentionally discards all events — used when quiet mode is active
    }
}

struct CommandLineParser: Sendable {
    private struct FlagValues {
        var scheme: String?
        var destination: String?
        var testTarget: String?
        var timeout: Double?
        var concurrency: Int?
        var noCache = false
        var output: String?
        var htmlOutput: String?
        var sonarOutput: String?
        var quiet = false
        var input: String?
    }

    func parse(_ arguments: [String]) throws -> ParsedArguments {
        guard !arguments.isEmpty else {
            return ParsedArguments(showHelp: true)
        }

        switch arguments[0] {
        case "--help", "-h":
            return ParsedArguments(showHelp: true)

        case "--version":
            return ParsedArguments(showVersion: true)

        default:
            break
        }

        var remaining = arguments
        var projectPath = "."

        if remaining[0] == "init" {
            remaining.removeFirst()
            if let next = remaining.first, !next.hasPrefix("-") {
                projectPath = next
            }

            return ParsedArguments(projectPath: projectPath, showInit: true)
        }

        if remaining[0] == "run" {
            remaining.removeFirst()
            if let next = remaining.first, !next.hasPrefix("-") {
                projectPath = next
                remaining.removeFirst()
            }
        }

        let flags = try parseFlags(remaining)

        return ParsedArguments(
            projectPath: projectPath,
            scheme: flags.scheme,
            destination: flags.destination,
            testTarget: flags.testTarget,
            timeout: flags.timeout,
            concurrency: flags.concurrency,
            noCache: flags.noCache,
            output: flags.output,
            htmlOutput: flags.htmlOutput,
            sonarOutput: flags.sonarOutput,
            quiet: flags.quiet,
            input: flags.input
        )
    }

    private func parseFlags(_ arguments: [String]) throws -> FlagValues {
        var values = FlagValues()
        var index = 0

        while index < arguments.count {
            try applyFlag(arguments[index], to: &values, at: &index, in: arguments)
            index += 1
        }

        return values
    }

    private func applyFlag(
        _ flag: String,
        to values: inout FlagValues,
        at index: inout Int,
        in arguments: [String]
    ) throws {
        switch flag {
        case "--scheme":
            values.scheme = try nextValue(for: flag, at: &index, in: arguments)

        case "--destination":
            values.destination = try nextValue(for: flag, at: &index, in: arguments)

        case "--target":
            values.testTarget = try nextValue(for: flag, at: &index, in: arguments)

        case "--timeout":
            values.timeout = try nextDouble(for: flag, at: &index, in: arguments)

        case "--concurrency":
            values.concurrency = try nextInt(for: flag, at: &index, in: arguments)

        case "--no-cache":
            values.noCache = true

        case "--output":
            values.output = try nextValue(for: flag, at: &index, in: arguments)

        case "--html-output":
            values.htmlOutput = try nextValue(for: flag, at: &index, in: arguments)

        case "--sonar-output":
            values.sonarOutput = try nextValue(for: flag, at: &index, in: arguments)

        case "--quiet":
            values.quiet = true

        case "--input":
            values.input = try nextValue(for: flag, at: &index, in: arguments)

        default:
            throw UsageError(message: "unknown option '\(flag)'")
        }
    }

    private func nextValue(for flag: String, at index: inout Int, in arguments: [String]) throws -> String {
        let next = index + 1
        guard next < arguments.count else {
            throw UsageError(message: "\(flag) requires a value")
        }
        index = next
        return arguments[next]
    }

    private func nextDouble(for flag: String, at index: inout Int, in arguments: [String]) throws -> Double {
        let raw = try nextValue(for: flag, at: &index, in: arguments)
        guard let value = Double(raw), value > 0 else {
            throw UsageError(message: "\(flag) must be a positive number")
        }
        return value
    }

    private func nextInt(for flag: String, at index: inout Int, in arguments: [String]) throws -> Int {
        let raw = try nextValue(for: flag, at: &index, in: arguments)
        guard let value = Int(raw) else {
            throw UsageError(message: "\(flag) must be an integer")
        }
        return value
    }

}

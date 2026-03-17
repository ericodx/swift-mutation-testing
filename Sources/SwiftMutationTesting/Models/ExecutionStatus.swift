enum ExecutionStatus: Sendable, Equatable {
    case killed(by: String)
    case killedByCrash
    case survived
    case unviable
    case timeout
    case noCoverage
}

extension ExecutionStatus: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case by
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "killed":
            self = .killed(by: try container.decode(String.self, forKey: .by))

        case "killedByCrash":
            self = .killedByCrash

        case "survived":
            self = .survived

        case "unviable":
            self = .unviable

        case "timeout":
            self = .timeout

        case "noCoverage":
            self = .noCoverage

        default:
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: kind)
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .killed(let by):
            try container.encode("killed", forKey: .kind)
            try container.encode(by, forKey: .by)

        case .killedByCrash:
            try container.encode("killedByCrash", forKey: .kind)

        case .survived:
            try container.encode("survived", forKey: .kind)

        case .unviable:
            try container.encode("unviable", forKey: .kind)

        case .timeout:
            try container.encode("timeout", forKey: .kind)

        case .noCoverage:
            try container.encode("noCoverage", forKey: .kind)
        }
    }
}

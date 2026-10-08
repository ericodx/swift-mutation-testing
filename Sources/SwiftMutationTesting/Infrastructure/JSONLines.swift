import Foundation

enum JSONLines {
    static func append(_ value: some Encodable, to path: String) throws {
        var line = try JSONEncoder().encode(value)
        line.append(UInt8(ascii: "\n"))

        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard FileManager.default.fileExists(atPath: path) else {
            try line.write(to: url)
            return
        }

        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    static func failureWarning(for path: String, error: any Error) -> String {
        "Warning: could not write to '\(path)' (\(error.localizedDescription)); "
            + "verdicts reached from now on may be lost if the run is interrupted"
    }

    static func read<Value: Decodable>(_: Value.Type, from path: String) -> [Value] {
        guard let data = FileManager.default.contents(atPath: path) else { return [] }

        return data.split(separator: UInt8(ascii: "\n")).compactMap { line in
            try? JSONDecoder().decode(Value.self, from: line)
        }
    }
}

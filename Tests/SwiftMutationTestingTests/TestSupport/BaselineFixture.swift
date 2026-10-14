import Foundation

@testable import SwiftMutationTesting

func makeBaseline(
    score: Double? = 80,
    scope: BaselineScope = BaselineScope(
        operators: OperatorRegistry.allOperatorNames, sourcesPath: ".", excludePatterns: []
    ),
    undetected fingerprints: [String] = []
) -> Baseline {
    Baseline(
        toolVersion: "1.6.0",
        createdAt: Date(timeIntervalSince1970: 1_790_000_000),
        score: score,
        scope: scope,
        undetected: fingerprints.enumerated().map { index, fingerprint in
            BaselineEntry(
                fingerprint: fingerprint,
                file: "Sources/Foo.swift",
                line: index + 1,
                operatorIdentifier: "RelationalOperatorReplacement",
                original: "<",
                replacement: "<=",
                status: "survived"
            )
        }
    )
}

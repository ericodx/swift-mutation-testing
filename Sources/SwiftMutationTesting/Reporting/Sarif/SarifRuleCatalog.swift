enum SarifRuleCatalog {
    static let helpUri =
        "https://github.com/ericodx/swift-mutation-testing/blob/main/Docs/USAGE.MD#operator-identifiers"

    static func rule(for operatorIdentifier: String) -> SarifRule {
        let mutationOperator = OperatorRegistry.mutationOperator(named: operatorIdentifier)
        let name = mutationOperator?.summary ?? operatorIdentifier
        let change = mutationOperator?.explanation ?? "Mutates the code."
        return SarifRule(
            id: operatorIdentifier,
            name: operatorIdentifier,
            shortDescription: SarifMessage(text: name),
            fullDescription: SarifMessage(text: change),
            helpUri: helpUri,
            defaultConfiguration: SarifConfiguration(level: "warning")
        )
    }
}

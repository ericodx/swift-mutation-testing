enum ReplacementKind: String, Sendable, Codable {
    case binaryOperator
    case prefixOperator
    case booleanLiteral
    case swapTernary
    case removeStatement
    case wrapWithNegation
}

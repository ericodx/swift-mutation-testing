extension String {
    var htmlEscaped: String {
        var escaped = ""
        escaped.reserveCapacity(utf8.count)
        for character in self {
            switch character {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            case "\"": escaped += "&quot;"
            case "'": escaped += "&#39;"
            default: escaped.append(character)
            }
        }
        return escaped
    }
}

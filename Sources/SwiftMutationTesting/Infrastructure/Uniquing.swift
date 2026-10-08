enum Uniquing {
    static func keepingFirst<Key: Hashable, Value>(_ pairs: some Sequence<(Key, Value)>) -> [Key: Value] {
        var result: [Key: Value] = [:]
        for (key, value) in pairs where result[key] == nil {
            result[key] = value
        }
        return result
    }

    static func keepingLast<Key: Hashable, Value>(_ pairs: some Sequence<(Key, Value)>) -> [Key: Value] {
        var result: [Key: Value] = [:]
        for (key, value) in pairs {
            result[key] = value
        }
        return result
    }
}

enum Uniquing {
    static func first<Value>(_ first: Value, _: Value) -> Value {
        first
    }

    static func last<Value>(_: Value, _ last: Value) -> Value {
        last
    }
}

import Foundation

/// Lightweight tuple replacement for former `RACTuple` usage in the connection layer.
public struct AppViewPair {
    public let first: Any?
    public let second: Any?

    public init(first: Any?, second: Any?) {
        self.first = first
        self.second = second
    }
}

public struct AppViewTriple {
    public let first: Any?
    public let second: Any?
    public let third: Any?

    public init(first: Any?, second: Any?, third: Any?) {
        self.first = first
        self.second = second
        self.third = third
    }
}

import Foundation

@objcMembers open class TestCase: NSObject {
    public required override init() {}

    open func setUp() {}

    open func tearDown() {}
}

public struct Failure: Equatable {
    public var message: String
    public var file: String
    public var line: UInt
}

public enum Report {
    nonisolated(unsafe) public private(set) static var failures: [Failure] = []
    nonisolated(unsafe) public private(set) static var skipped: String?

    public static func reset() {
        failures = []
        skipped = nil
    }

    public static func record(_ message: String, _ file: StaticString, _ line: UInt) {
        failures.append(Failure(message: message, file: name(of: file), line: line))
    }

    public static func skip(_ reason: String) {
        skipped = reason
    }

    static func name(of file: StaticString) -> String {
        ("\(file)" as NSString).lastPathComponent
    }
}

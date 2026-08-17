import Foundation

public func fail(
    _ message: String = "unconditional failure",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    Report.record(message, file, line)
}

public func skip(_ reason: String) {
    Report.skip(reason)
}

public func expectEqual<T: Equatable>(
    _ actual: T,
    _ expected: T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard actual != expected else { return }
    Report.record(explain("expected \(expected), got \(actual)", message()), file, line)
}

public func expectEqual<T: FloatingPoint>(
    _ actual: T,
    _ expected: T,
    accuracy: T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard abs(actual - expected) > accuracy else { return }
    Report.record(explain("expected \(expected) ± \(accuracy), got \(actual)", message()), file, line)
}

public func expectNotEqual<T: Equatable>(
    _ actual: T,
    _ unexpected: T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard actual == unexpected else { return }
    Report.record(explain("expected anything but \(unexpected)", message()), file, line)
}

public func expectNil<T>(
    _ value: T?,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard let value else { return }
    Report.record(explain("expected nil, got \(value)", message()), file, line)
}

public func expectNotNil<T>(
    _ value: T?,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard value == nil else { return }
    Report.record(explain("expected a value, got nil", message()), file, line)
}

public func expectTrue(
    _ value: Bool,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard !value else { return }
    Report.record(explain("expected true", message()), file, line)
}

public func expectFalse(
    _ value: Bool,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard value else { return }
    Report.record(explain("expected false", message()), file, line)
}

public func expectGreaterThan<T: Comparable>(
    _ actual: T,
    _ limit: T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard actual <= limit else { return }
    Report.record(explain("expected \(actual) > \(limit)", message()), file, line)
}

public func expectLessThan<T: Comparable>(
    _ actual: T,
    _ limit: T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard actual >= limit else { return }
    Report.record(explain("expected \(actual) < \(limit)", message()), file, line)
}

public func expectAtLeast<T: Comparable>(
    _ actual: T,
    _ limit: T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard actual < limit else { return }
    Report.record(explain("expected \(actual) >= \(limit)", message()), file, line)
}

public func expectAtMost<T: Comparable>(
    _ actual: T,
    _ limit: T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard actual > limit else { return }
    Report.record(explain("expected \(actual) <= \(limit)", message()), file, line)
}

func explain(_ reason: String, _ message: String) -> String {
    message.isEmpty ? reason : "\(reason) — \(message)"
}

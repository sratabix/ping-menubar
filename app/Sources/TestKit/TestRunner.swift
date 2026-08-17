import Foundation

public enum TestRunner {
    public static func run(_ suites: [TestCase.Type]) -> Never {
        var passed = 0
        var skipped = 0
        var failed = 0
        var failures: [String] = []

        for suite in suites {
            let name = String(describing: suite)
            for test in names(in: suite) {
                Report.reset()
                let instance = suite.init()
                instance.setUp()
                _ = instance.perform(NSSelectorFromString(test))
                instance.tearDown()

                if !Report.failures.isEmpty {
                    failed += 1
                    for failure in Report.failures {
                        failures.append("\(name).\(test)  \(failure.file):\(failure.line)  \(failure.message)")
                    }
                } else if let reason = Report.skipped {
                    skipped += 1
                    print("skip  \(name).\(test)  \(reason)")
                } else {
                    passed += 1
                }
            }
        }

        for failure in failures { print("fail  \(failure)") }
        let total = passed + skipped + failed
        print("\(total) tests in \(suites.count) suites: \(passed) passed, \(skipped) skipped, \(failed) failed")
        exit(failed == 0 ? 0 : 1)
    }

    static func names(in suite: TestCase.Type) -> [String] {
        var count: UInt32 = 0
        guard let methods = class_copyMethodList(suite, &count) else { return [] }
        defer { free(methods) }
        return (0..<Int(count))
            .map { NSStringFromSelector(method_getName(methods[$0])) }
            .filter { $0.hasPrefix("test") && !$0.contains(":") }
            .sorted()
    }
}

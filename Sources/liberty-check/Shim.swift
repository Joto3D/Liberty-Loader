import Foundation

// XCTest stand-ins. Every assertion really asserts: a failure records file:line plus
// expected-vs-actual, bumps the current test's failure count, and the run exits non-zero.

enum Harness {
    /// Failures recorded for the test currently executing.
    nonisolated(unsafe) static var currentFailures: [String] = []
}

/// Thrown by `XCTSkip(...)` to stop a test without failing it.
struct XCTSkip: Error, CustomStringConvertible {
    let reason: String
    init(_ reason: String = "skipped", file: StaticString = #filePath, line: UInt = #line) {
        self.reason = reason
    }
    var description: String { reason }
}

/// Thrown by XCTUnwrap after it has recorded a failure, to stop the test.
struct XCTUnwrapFailure: Error {}

/// Minimal XCTestCase: fresh instance per test, setUp/tearDown hooks.
class XCTestCase {
    required init() {}
    func setUpWithError() throws {}
    func tearDownWithError() throws {}
}

private func record(_ summary: String, _ message: String, _ file: StaticString, _ line: UInt) {
    let extra = message.isEmpty ? "" : " - \(message)"
    Harness.currentFailures.append("\(file):\(line): \(summary)\(extra)")
}

func XCTFail(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    record("failed", message, file, line)
}

func XCTAssertEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T,
                                  _ message: @autoclosure () -> String = "",
                                  file: StaticString = #filePath, line: UInt = #line) {
    do {
        let x = try a(), y = try b()
        if x != y { record("XCTAssertEqual failed: (\(x)) is not equal to (\(y))", message(), file, line) }
    } catch {
        record("XCTAssertEqual threw \(error)", message(), file, line)
    }
}

func XCTAssertEqual<T: FloatingPoint>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T,
                                      accuracy: T, _ message: @autoclosure () -> String = "",
                                      file: StaticString = #filePath, line: UInt = #line) {
    do {
        let x = try a(), y = try b()
        // Written so NaN fails and equal infinities pass, like XCTest.
        if !(x == y || abs(x - y) <= accuracy) {
            record("XCTAssertEqual failed: (\(x)) is not equal to (\(y)) +/- (\(accuracy))", message(), file, line)
        }
    } catch {
        record("XCTAssertEqual threw \(error)", message(), file, line)
    }
}

func XCTAssertTrue(_ e: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "",
                   file: StaticString = #filePath, line: UInt = #line) {
    do { if try !e() { record("XCTAssertTrue failed (expected true, got false)", message(), file, line) } }
    catch { record("XCTAssertTrue threw \(error)", message(), file, line) }
}

func XCTAssertFalse(_ e: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "",
                    file: StaticString = #filePath, line: UInt = #line) {
    do { if try e() { record("XCTAssertFalse failed (expected false, got true)", message(), file, line) } }
    catch { record("XCTAssertFalse threw \(error)", message(), file, line) }
}

func XCTAssertNil(_ e: @autoclosure () throws -> Any?, _ message: @autoclosure () -> String = "",
                  file: StaticString = #filePath, line: UInt = #line) {
    do { if let v = try e() { record("XCTAssertNil failed: expected nil, got (\(v))", message(), file, line) } }
    catch { record("XCTAssertNil threw \(error)", message(), file, line) }
}

func XCTAssertNotNil(_ e: @autoclosure () throws -> Any?, _ message: @autoclosure () -> String = "",
                     file: StaticString = #filePath, line: UInt = #line) {
    do { if try e() == nil { record("XCTAssertNotNil failed: expected non-nil, got nil", message(), file, line) } }
    catch { record("XCTAssertNotNil threw \(error)", message(), file, line) }
}

func XCTUnwrap<T>(_ e: @autoclosure () throws -> T?, _ message: @autoclosure () -> String = "",
                  file: StaticString = #filePath, line: UInt = #line) throws -> T {
    let value: T?
    do { value = try e() } catch {
        record("XCTUnwrap threw \(error)", message(), file, line)
        throw XCTUnwrapFailure()
    }
    guard let value else {
        record("XCTUnwrap failed: expected non-nil value of type \"\(T.self)\"", message(), file, line)
        throw XCTUnwrapFailure()
    }
    return value
}

func XCTAssertThrowsError<T>(_ e: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "",
                             file: StaticString = #filePath, line: UInt = #line,
                             _ errorHandler: (Error) -> Void = { _ in }) {
    do {
        let v = try e()
        record("XCTAssertThrowsError failed: did not throw an error (returned \(v))", message(), file, line)
    } catch {
        errorHandler(error)
    }
}

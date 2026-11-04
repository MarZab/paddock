import Foundation
import PaddockCore

enum Fixture {
    /// Loads `Fixtures/<directory>/<name>` from the test bundle.
    static func data(_ directory: String, _ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: directory) else {
            throw FixtureError.missing("\(directory)/\(name)")
        }
        return try Data(contentsOf: url)
    }

    static func decode<T: Decodable>(_ type: T.Type, _ directory: String, _ name: String) throws -> T {
        try JSONCoding.decode(type, from: data(directory, name))
    }
}

enum FixtureError: Error {
    case missing(String)
}

/// Returns canned results per argument list, and records every call.
final class FakeRunner: ProcessRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [[String]: ProcessResult] = [:]
    private var effects: [(matches: @Sendable ([String]) -> Bool, effect: @Sendable () -> Void)] = []
    private var hangs: [@Sendable ([String]) -> Bool] = []
    private var matchedResponses: [(matches: @Sendable ([String]) -> Bool, result: ProcessResult)] = []
    private(set) var calls: [[String]] = []
    private(set) var environments: [[String: String]?] = []
    /// Answer commands without a canned response with exit 0 and no output.
    var succeedByDefault = false

    func respond(to arguments: [String], with stdout: Data, exitCode: Int32 = 0, stderr: String = "") {
        lock.withLock {
            responses[arguments] = ProcessResult(exitCode: exitCode, stdout: stdout, stderr: Data(stderr.utf8))
        }
    }

    /// Runs `effect` after each call `matches` accepts, so a command can change later answers
    /// (say, `sbx template load` adding to `sbx template ls`).
    /// Like `respond(to:)`, for calls whose arguments are not known in advance (temporary paths).
    func respond(when matches: @escaping @Sendable ([String]) -> Bool, with stdout: Data, exitCode: Int32 = 0, stderr: String = "") {
        lock.withLock { matchedResponses.append((matches, ProcessResult(exitCode: exitCode, stdout: stdout, stderr: Data(stderr.utf8)))) }
    }

    func whenCalled(_ matches: @escaping @Sendable ([String]) -> Bool, _ effect: @escaping @Sendable () -> Void) {
        lock.withLock { effects.append((matches, effect)) }
    }

    /// Makes a call `matches` accepts wait until its task is cancelled, like a command that never returns.
    func hang(when matches: @escaping @Sendable ([String]) -> Bool) {
        lock.withLock { hangs.append(matches) }
    }

    func run(_ executable: URL, arguments: [String], environment: [String: String]?, stdin: Data?) async throws -> ProcessResult {
        let (result, triggered) = lock.withLock {
            calls.append(arguments)
            environments.append(environment)
            let triggered = effects.filter { $0.matches(arguments) }.map(\.effect)
            if let response = responses[arguments] { return (response, triggered) }
            if let match = matchedResponses.last(where: { $0.matches(arguments) }) { return (match.result, triggered) }
            return (succeedByDefault
                ? ProcessResult(exitCode: 0, stdout: Data(), stderr: Data())
                : ProcessResult(exitCode: 127, stdout: Data(), stderr: Data("no fake response".utf8)), triggered)
        }
        // Outside the lock: an effect usually calls `respond`.
        for effect in triggered { effect() }
        if lock.withLock({ hangs.contains { $0(arguments) } }) { try await Task.sleep(for: .seconds(3600)) }
        return result
    }
}

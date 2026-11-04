import Foundation

/// llmman's hardening checks (backlog doc Models, Hardening). Any red check blocks embedding
/// llmman's UI and creating projects that use local models.
public struct LlmmanHealth: Sendable, Equatable {
    public enum Status: Sendable, Equatable, Comparable {
        case green, yellow, red
    }

    public enum Kind: String, Sendable, Equatable, CaseIterable {
        /// llmman answers `/api/version`.
        case reachable
        /// `GET /llmman/shell` reports the web shell as disabled.
        case shellOff
        /// llmman listens on loopback only.
        case loopbackOnly
        /// llmman listens on the port Paddock denies to every sandbox.
        case expectedPort
        /// `prompts.jsonl` holds prompts (yellow, with a clear action).
        case promptHistory
    }

    public struct Check: Sendable, Equatable {
        public let kind: Kind
        public let status: Status
        public let detail: String
    }

    public let checks: [Check]

    public var overall: Status { checks.map(\.status).max() ?? .red }

    /// Whether the embedded UI and local-model projects are allowed.
    public var allowsLocalModels: Bool { !checks.isEmpty && !checks.contains { $0.status == .red } }

    public func check(_ kind: Kind) -> Check? { checks.first { $0.kind == kind } }
}

/// An address llmman listens on, from `lsof -F n`.
public struct ListenAddress: Sendable, Equatable {
    public let host: String
    public let port: Int

    public var isLoopback: Bool {
        host == "::1" || host == "localhost" || host.hasPrefix("127.")
    }

    /// Parses lsof's field output (`-F n`): lines starting with `n` name a socket, such as
    /// `n127.0.0.1:17434`, `n[::1]:17434`, or `n*:17434`. Other lines (`p`, `f`) are ignored.
    public static func parse(lsofFields output: String) -> [ListenAddress] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            guard line.first == "n", let colon = line.lastIndex(of: ":"),
                  let port = Int(line[line.index(after: colon)...]) else { return nil }
            var host = String(line[line.index(after: line.startIndex)..<colon])
            if host.hasPrefix("["), host.hasSuffix("]") {
                host = String(host.dropFirst().dropLast())
            }
            return ListenAddress(host: host, port: port)
        }
    }
}

public enum LlmmanHealthEvaluator {
    /// Turns what was observed into checks. Anything that could not be observed is red:
    /// a check Paddock cannot confirm is not green.
    public static func evaluate(
        version: LlmmanVersion?,
        shell: LlmmanShellStatus?,
        listeners: [ListenAddress]?,
        promptHistoryBytes: Int64?,
        expectedPort: Int = AppConfig.llmmanPort
    ) -> LlmmanHealth {
        var checks: [LlmmanHealth.Check] = []

        if let version {
            checks.append(.init(kind: .reachable, status: .green, detail: "llmman \(version.version)"))
        } else {
            checks.append(.init(kind: .reachable, status: .red, detail: "llmman does not answer on 127.0.0.1:\(expectedPort); is the sbx daemon running?"))
        }

        switch shell?.enabled {
        case false?:
            checks.append(.init(kind: .shellOff, status: .green, detail: shell?.reason ?? "web shell is off"))
        case true?:
            checks.append(.init(kind: .shellOff, status: .red, detail: "llmman's web shell is on: any local web page could run commands as you"))
        case nil:
            checks.append(.init(kind: .shellOff, status: .red, detail: "cannot read the web shell's status"))
        }

        switch listeners {
        case nil, []?:
            checks.append(.init(kind: .loopbackOnly, status: .red, detail: "cannot see which addresses llmman listens on"))
            checks.append(.init(kind: .expectedPort, status: .red, detail: "cannot see llmman's port"))
        case let addresses?:
            let exposed = addresses.filter { !$0.isLoopback }
            if exposed.isEmpty {
                checks.append(.init(kind: .loopbackOnly, status: .green, detail: "listens on loopback only"))
            } else {
                let list = exposed.map { "\($0.host):\($0.port)" }.joined(separator: ", ")
                checks.append(.init(kind: .loopbackOnly, status: .red, detail: "llmman also listens on \(list)"))
            }
            let ports = Set(addresses.map(\.port))
            if ports.contains(expectedPort) {
                checks.append(.init(kind: .expectedPort, status: .green, detail: "port \(expectedPort), denied to every sandbox"))
            } else {
                let list = ports.sorted().map(String.init).joined(separator: ", ")
                checks.append(.init(kind: .expectedPort, status: .red,
                                    detail: "llmman listens on \(list), but Paddock denies \(expectedPort) to sandboxes"))
            }
        }

        switch promptHistoryBytes {
        case nil, 0?:
            checks.append(.init(kind: .promptHistory, status: .green, detail: "no saved prompts"))
        case let bytes?:
            let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            checks.append(.init(kind: .promptHistory, status: .yellow, detail: "llmman has saved \(size) of prompts"))
        }
        return LlmmanHealth(checks: checks)
    }
}

/// Gathers what the evaluator needs from the running system.
public struct LlmmanHealthChecker: Sendable {
    public static let lsof = URL(fileURLWithPath: "/usr/sbin/lsof")

    private let api: LlmmanAPI
    private let runner: any ProcessRunner
    private let promptHistoryPath: String

    public init(api: LlmmanAPI, runner: any ProcessRunner, home: String) {
        self.api = api
        self.runner = runner
        self.promptHistoryPath = Self.promptHistoryPath(home: home)
    }

    /// Where sbx's llmman saves prompts (M0 round 3).
    public static func promptHistoryPath(home: String) -> String {
        home + "/.local/share/llmman/prompts.jsonl"
    }

    public func check() async -> LlmmanHealth {
        let version = try? await api.version()
        let shell = try? await api.shellStatus()
        var listeners: [ListenAddress]?
        if let pid = version?.pid {
            listeners = await self.listeners(pid: pid)
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: promptHistoryPath))?[.size] as? NSNumber
        return LlmmanHealthEvaluator.evaluate(version: version, shell: shell, listeners: listeners,
                                              promptHistoryBytes: size?.int64Value)
    }

    /// TCP listening sockets of llmman's process. lsof exits 1 when it finds none.
    func listeners(pid: Int) async -> [ListenAddress]? {
        let arguments = ["-nP", "-a", "-p", String(pid), "-iTCP", "-sTCP:LISTEN", "-F", "n"]
        guard let result = try? await runner.run(Self.lsof, arguments: arguments), result.exitCode == 0 else { return nil }
        return ListenAddress.parse(lsofFields: String(decoding: result.stdout, as: UTF8.self))
    }

    /// Empties `prompts.jsonl` in place, keeping its owner-only permissions. Only on operator request.
    public func clearPromptHistory() throws {
        guard FileManager.default.fileExists(atPath: promptHistoryPath) else { return }
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: promptHistoryPath))
        defer { try? handle.close() }
        try handle.truncate(atOffset: 0)
    }
}

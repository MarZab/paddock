import Foundation

/// Something Paddock needs on the host. Paddock never installs it: it only detects it and shows
/// the example command, which the operator runs (backlog doc Overview, Dependencies are the operator's job).
public struct Dependency: Sendable, Equatable, Identifiable {
    public let id: String
    public let displayName: String
    public let minimumVersion: SemanticVersion
    /// Documentation only, never executed by Paddock.
    public let exampleInstall: String

    public static let sbx = Dependency(
        id: "sbx",
        displayName: "Docker Sandboxes (sbx, includes llmman)",
        minimumVersion: SbxService.minimumVersion,
        exampleInstall: "brew install docker/tap/sbx"
    )

    /// What the app needs at runtime. XcodeGen and the other dev tools come from `mise install`.
    public static let required: [Dependency] = [.sbx]
}

public struct DependencyReport: Sendable, Equatable, Identifiable {
    public enum State: Sendable, Equatable {
        case ok(version: String)
        case missing
        case tooOld(found: String)
        /// Found, but its version could not be read.
        case unknownVersion(reason: String)
    }

    public let dependency: Dependency
    public let path: String?
    public let state: State

    public var id: String { dependency.id }

    public var isSatisfied: Bool {
        if case .ok = state { return true }
        return false
    }
}

public struct DependencyCheck: Sendable {
    private let locator: BinaryLocator
    private let runner: any ProcessRunner

    public init(locator: BinaryLocator, runner: any ProcessRunner) {
        self.locator = locator
        self.runner = runner
    }

    public func check() async -> [DependencyReport] {
        var reports: [DependencyReport] = []
        for dependency in Dependency.required {
            reports.append(await check(dependency))
        }
        return reports
    }

    func check(_ dependency: Dependency) async -> DependencyReport {
        guard let url = locator.locate(dependency.id) else {
            return DependencyReport(dependency: dependency, path: nil, state: .missing)
        }
        let state: DependencyReport.State
        switch await clientVersion(of: dependency, at: url) {
        case .success(let text):
            if let found = SemanticVersion(parsing: text) {
                state = found >= dependency.minimumVersion ? .ok(version: text) : .tooOld(found: text)
            } else {
                state = .unknownVersion(reason: "cannot read version \(text)")
            }
        case .failure(let reason):
            state = .unknownVersion(reason: reason.message)
        }
        return DependencyReport(dependency: dependency, path: url.path, state: state)
    }

    struct Reason: Error {
        let message: String
    }

    /// Only sbx so far: `sbx version --json` reports the client version even when the daemon is down.
    private func clientVersion(of dependency: Dependency, at url: URL) async -> Result<String, Reason> {
        do {
            let result = try await runner.run(url, arguments: ["version", "--json"])
            let version = try JSONCoding.decode(SbxVersion.self, from: result.stdout)
            return .success(version.client.version)
        } catch {
            return .failure(Reason(message: String(describing: error)))
        }
    }
}

/// The operator's login-shell PATH, so binaries installed by Homebrew, mise, and the like are
/// found even though a GUI app starts with a minimal environment.
public enum LoginShell {
    public static let zsh = URL(fileURLWithPath: "/bin/zsh")

    public static func path(runner: any ProcessRunner) async -> String? {
        guard let result = try? await runner.run(zsh, arguments: ["-l", "-c", "printf %s \"$PATH\""]),
              result.exitCode == 0 else { return nil }
        let path = String(decoding: result.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }
}

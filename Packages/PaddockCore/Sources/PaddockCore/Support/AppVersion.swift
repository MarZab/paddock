import Foundation

/// The running build's version (backlog doc UI, Version): `yymmdd.N` from `tools/tasks/version.sh`,
/// which `mise run build` and `mise run install` write into the app's Info.plist with the commit
/// count and the short commit hash. A build from Xcode alone keeps the placeholders and is unversioned.
public struct AppVersion: Sendable, Equatable {
    /// `yymmdd.N`, or nil for an unversioned build.
    public let version: String?
    /// The commit count, or nil when unknown.
    public let build: String?
    /// The short commit hash, without `-dirty`.
    public let commit: String?
    /// The build had uncommitted changes.
    public let isDirty: Bool

    /// Info.plist keys: the version and build are Apple's, the commit is Paddock's own.
    public static let versionKey = "CFBundleShortVersionString"
    public static let buildKey = "CFBundleVersion"
    public static let commitKey = "PaddockCommit"

    /// project.yml's placeholders, which a build outside mise keeps.
    static let unversioned: Set<String> = ["", "0", "0.0"]

    public init(info: [String: Any]) {
        func value(_ key: String) -> String? {
            guard let text = (info[key] as? String)?.trimmingCharacters(in: .whitespaces),
                  !Self.unversioned.contains(text) else { return nil }
            return text
        }
        version = value(Self.versionKey)
        build = value(Self.buildKey)
        let commit = value(Self.commitKey)
        if let commit, commit.hasSuffix("-dirty") {
            self.commit = String(commit.dropLast("-dirty".count))
            isDirty = true
        } else {
            self.commit = commit
            isDirty = false
        }
    }

    /// What the sidebar shows next to the status button.
    public var label: String {
        version ?? "unversioned"
    }

    /// The tooltip: the version, which commit it is, and whether it had uncommitted changes.
    public var help: String {
        guard let version else {
            return "Unversioned build: built without mise (mise run build or mise run install sets the version)"
        }
        var line = "Paddock \(version)"
        if let commit {
            line += ", commit \(commit)"
        }
        if let build {
            line += " (build \(build))"
        }
        if isDirty {
            line += "\nBuilt with uncommitted changes"
        }
        return line
    }
}

import Foundation

/// Where Paddock keeps its files: one folder, `$XDG_CONFIG_HOME/paddock` or `~/.config/paddock`.
public struct PaddockPaths: Sendable, Equatable {
    public let configDirectory: String

    public init(configDirectory: String) {
        self.configDirectory = configDirectory
    }

    public init(environment: [String: String], home: String) {
        let base = environment["XDG_CONFIG_HOME"].flatMap { $0.hasPrefix("/") ? $0 : nil } ?? home + "/.config"
        self.init(configDirectory: base + "/paddock")
    }

    /// The operator's config (backlog doc App config).
    public var appConfig: String { configDirectory + "/paddock.yaml" }
    /// One `<name>.json` per project.
    public var projects: String { configDirectory + "/projects" }
    public var kits: String { configDirectory + "/kits" }

    /// Makes Paddock's config folders owner-only (0700) and the files in them 0600, whatever they
    /// were created with (PAD-94). Approvals in `projects/` and the overlays are the operator's
    /// alone; other software running as the same user should not read or change them casually.
    /// Missing folders are skipped, and a failure is ignored: this is hardening, not a gate.
    public func secure() {
        let manager = FileManager.default
        for directory in [configDirectory, projects, kits] {
            guard manager.fileExists(atPath: directory) else { continue }
            try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory)
        }
        for directory in [projects, kits] {
            guard let enumerator = manager.enumerator(atPath: directory) else { continue }
            while let relative = enumerator.nextObject() as? String {
                let path = directory + "/" + relative
                var isDirectory: ObjCBool = false
                guard manager.fileExists(atPath: path, isDirectory: &isDirectory) else { continue }
                // A link would point the change at something that is not Paddock's.
                if (try? manager.attributesOfItem(atPath: path))?[.type] as? FileAttributeType == .typeSymbolicLink { continue }
                try? manager.setAttributes([.posixPermissions: isDirectory.boolValue ? 0o700 : 0o600], ofItemAtPath: path)
            }
        }
        if manager.fileExists(atPath: appConfig),
           (try? manager.attributesOfItem(atPath: appConfig))?[.type] as? FileAttributeType == .typeRegular {
            try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: appConfig)
        }
    }
}

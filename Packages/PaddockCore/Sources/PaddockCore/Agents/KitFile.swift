import Foundation

/// A Paddock kit's v3 descriptor, `<dir>/<dir>.yaml` (sbx reads a local kit folder by that name;
/// backlog doc Kits), rewritten whenever it differs from what Paddock ships. The `spec.yaml` of the
/// v1/v2 kits from before PAD-73.2 is removed.
enum KitFile {
    /// Every Paddock kit's `version` (sbx refuses a `provides` without one). The kit's recorded
    /// reference carries a hash of the file, so a change is still told apart from the version.
    static let version = "1.0.0"

    /// The descriptor's path in a kit folder.
    static func file(in dir: String) -> String { dir + "/" + (dir as NSString).lastPathComponent + ".yaml" }

    /// Writes the descriptor, and `<dir>/<dir>.dockerfile` when the kit has files of its own.
    static func write(_ spec: String, to dir: String, dockerfile: String? = nil) throws -> String {
        try? FileManager.default.removeItem(atPath: dir + "/spec.yaml")
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var files = [(file(in: dir), spec)]
        if let dockerfile { files.append((dir + "/" + (dir as NSString).lastPathComponent + ".dockerfile", dockerfile)) }
        for (path, text) in files {
            let data = Data(text.utf8)
            if FileManager.default.contents(atPath: path) != data {
                try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            }
        }
        return dir
    }
}

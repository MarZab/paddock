import Foundation
import PaddockCore

/// The Log page's lines also go to a file of this session's own in `~/Library/Logs/Paddock`
/// (`LogFiles.name`), so what a create reported survives a restart of the app. Plain text, one
/// line per entry, written as it happens from whatever thread logs it, so the file keeps what
/// background work reported even while the main thread is stuck (PAD-78). Never a secret: only errors and the lines long work reports (`LogSink`). At
/// launch, Paddock's logs last written over a week ago are removed.
final class LogFile: @unchecked Sendable {
    static let shared = LogFile()

    private let lock = NSLock()
    let url: URL
    private var handle: FileHandle?

    var path: String { url.path }
    /// `~/Library/Logs/Paddock`, where every session's file is.
    var folder: URL { url.deletingLastPathComponent() }

    /// The earlier sessions' files, newest first (the Log page's session picker, PAD-78).
    func sessions() -> [LogFiles.Session] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return LogFiles.sessions(names, current: url.lastPathComponent)
    }

    /// An earlier session's lines, read off the main thread.
    func entries(ofSession name: String) async -> [LogEntry] {
        let file = folder.appendingPathComponent(name)
        let text = await Task.detached { (try? String(contentsOf: file, encoding: .utf8)) ?? "" }.value
        return LogFiles.entries(in: text)
    }

    private init() {
        let files = FileManager.default
        let folder = files.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Paddock")
        let name = LogFiles.name(started: Date(), pid: ProcessInfo.processInfo.processIdentifier)
        url = folder.appendingPathComponent(name)
        try? files.createDirectory(at: folder, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
        Self.prune(folder, current: name)
        files.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        handle = try? FileHandle(forWritingTo: url)
    }

    private static func prune(_ folder: URL, current: String) {
        let found = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let dated = found.compactMap { file -> (name: String, modified: Date)? in
            let values = try? file.resourceValues(forKeys: [.contentModificationDateKey])
            return values?.contentModificationDate.map { (file.lastPathComponent, $0) }
        }
        for name in LogFiles.toRemove(dated, current: current) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    func append(_ entry: LogEntry) {
        let line = entry.fileLine + "\n"
        lock.withLock { try? handle?.write(contentsOf: Data(line.utf8)) }
    }
}

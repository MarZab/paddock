import Foundation

/// Where a link the operator clicks in an A2UI tab goes (PAD-152; backlog doc Browser, interactive
/// tabs): an http(s) page opens as a tab of the sandbox's browser (`A2UICommands.open`), a path
/// relative to the tab's messages as a native tab of that file (`A2UICommands.openFile`). Nothing
/// else opens: not `mailto:`, `file:`, `javascript:`, an absolute path, or a path out of the folder.
public enum A2UILink: Sendable, Equatable {
    case web(URL)
    case file(String)

    public init?(_ destination: String) {
        let text = destination.trimmingCharacters(in: .whitespaces)
        if let scheme = A2UIMedia.scheme(of: text) {
            guard ["http", "https"].contains(scheme), let url = URL(string: text), url.host?.isEmpty == false else { return nil }
            self = .web(url)
            return
        }
        // A file's fragment or query is not part of its path.
        let path = String(text.prefix { $0 != "#" && $0 != "?" })
        let decoded = path.removingPercentEncoding ?? path
        guard !decoded.isEmpty, NativeShowPolicy.isRelativePath(decoded) else { return nil }
        self = .file(decoded)
    }
}

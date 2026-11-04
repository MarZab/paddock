import Foundation

/// Finds executables in the fixed lookup directories plus the operator's login-shell PATH.
public struct BinaryLocator: Sendable {
    /// Searched first, in this order, before the login PATH.
    public static let defaultDirectories = ["/opt/homebrew/bin", "/usr/local/bin"]

    public let searchPath: [String]
    private let isExecutable: @Sendable (String) -> Bool

    /// - Parameter loginPath: the value of `$PATH` from `/bin/zsh -lc 'echo $PATH'`, resolved once at launch.
    public init(
        loginPath: String?,
        directories: [String] = BinaryLocator.defaultDirectories,
        isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) {
        var seen = Set<String>()
        var path: [String] = []
        let fromLogin = (loginPath ?? "")
            .split(separator: ":")
            .map(String.init)
            .filter { $0.hasPrefix("/") }
        for dir in directories + fromLogin where seen.insert(dir).inserted {
            path.append(dir)
        }
        self.searchPath = path
        self.isExecutable = isExecutable
    }

    public func locate(_ name: String) -> URL? {
        for dir in searchPath {
            let candidate = (dir as NSString).appendingPathComponent(name)
            if isExecutable(candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }
}

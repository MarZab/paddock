/// A `major.minor.patch` version, parsed leniently from tool output such as
/// `v0.49.2` (sbx) or `0.1.571 (d76ad9e)` (llmman).
public struct SemanticVersion: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(_ major: Int, _ minor: Int, _ patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public init?(parsing text: String) {
        var rest = Substring(text.trimmingCharacters(in: .whitespaces))
        if rest.first == "v" || rest.first == "V" {
            rest = rest.dropFirst()
        }
        let core = rest.prefix { $0.isNumber || $0 == "." }
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard let value = Int(part) else { return nil }
            numbers.append(value)
        }
        while numbers.count < 3 {
            numbers.append(0)
        }
        self.init(numbers[0], numbers[1], numbers[2])
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    public var description: String { "\(major).\(minor).\(patch)" }
}

import Foundation

/// A voice installed on the Mac (AVSpeechSynthesisVoice, backlog doc Voice, Speaking).
public struct SpeechVoice: Sendable, Equatable, Identifiable {
    /// macOS's three kinds: basic voices come with it; enhanced and premium ones are downloaded in
    /// System Settings and sound far better.
    public enum Quality: Int, Sendable, Comparable {
        case basic, enhanced, premium

        public static func < (lhs: Quality, rhs: Quality) -> Bool { lhs.rawValue < rhs.rawValue }

        public var title: String {
            switch self {
            case .basic: "Basic"
            case .enhanced: "Enhanced"
            case .premium: "Premium"
            }
        }
    }

    public let id: String
    public let name: String
    /// BCP 47, such as "en-US".
    public let language: String
    public let quality: Quality
    /// A novelty voice (Bells, Bad News, and the like): never picked or offered.
    public let isNovelty: Bool

    public init(id: String, name: String, language: String, quality: Quality, isNovelty: Bool = false) {
        self.id = id
        self.name = name
        self.language = language
        self.quality = quality
        self.isNovelty = isNovelty
    }
}

/// Which voice speaks: the one the operator chose while it is installed, else the best for the
/// Mac's language. And whether to suggest downloading a better one.
public enum SpeechVoices {
    /// The voices for `language` ("en-US" or "en_US"), best first: higher quality, then the same
    /// region, then by name. Other regions of the language count ("en-GB" for "en-US").
    public static func offered(_ voices: [SpeechVoice], language: String) -> [SpeechVoice] {
        let wanted = normalized(language)
        let base = baseLanguage(wanted)
        return voices
            .filter { !$0.isNovelty && baseLanguage(normalized($0.language)) == base }
            .sorted { lhs, rhs in
                if lhs.quality != rhs.quality { return lhs.quality > rhs.quality }
                let lhsRegion = normalized(lhs.language) == wanted, rhsRegion = normalized(rhs.language) == wanted
                if lhsRegion != rhsRegion { return lhsRegion }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    /// The voice to speak with: `chosen` while it is installed, else the best offered. Nil leaves
    /// it to the system.
    public static func pick(_ voices: [SpeechVoice], language: String, chosen: String?) -> SpeechVoice? {
        if let chosen, let voice = voices.first(where: { $0.id == chosen }) { return voice }
        return offered(voices, language: language).first
    }

    /// Only basic voices for the language: a better one is a download away.
    public static func suggestsBetter(_ voices: [SpeechVoice], language: String) -> Bool {
        (offered(voices, language: language).first?.quality ?? .basic) == .basic
    }

    private static func normalized(_ language: String) -> String {
        language.replacingOccurrences(of: "_", with: "-").lowercased()
    }

    private static func baseLanguage(_ language: String) -> String {
        String(language.split(separator: "-").first ?? "")
    }
}

import Foundation

/// Where an A2UI tab's Image, Video, and AudioPlayer get their bytes (PAD-146; backlog doc Browser,
/// interactive tabs). The Mac never fetches a URL an agent chose: that would skip the sandbox's
/// network rules and reach llmman, the gateways, and the operator's network. A web URL is fetched
/// inside the sandbox, a relative path is a file next to the tab's messages there, and a `data:`
/// URL is decoded on the Mac. Anything else shows nothing.
public enum A2UIMedia {
    /// What a URL is for: the MIME family its bytes must have.
    public enum Kind: String, Sendable, CaseIterable {
        case image, video, audio
    }

    /// Where the bytes come from.
    public enum Source: Sendable, Equatable {
        /// Fetched inside the sandbox (`A2UICommands.fetch`).
        case sandboxFetch(URL)
        /// A file next to the tab's messages in the sandbox (`A2UICommands.read`).
        case sandboxFile(String)
        /// The bytes of a `data:` URL.
        case inline(mimeType: String, data: Data)
    }

    /// Why a URL shows nothing, for the placeholder the tab draws instead.
    public struct Refusal: Error, Sendable, Equatable {
        public var reason: String
    }

    /// Most bytes one image, video, or audio clip may have: what fits the largest output Paddock
    /// reads from `sbx exec`, as base64 (`FoundationProcessRunner.defaultMaxOutputBytes`).
    public static let maxBytes = 40 * 1024 * 1024

    /// The source for an A2UI component's `url` (or a Video's `posterUrl`, an image).
    public static func source(for url: String, kind: Kind) -> Result<Source, Refusal> {
        let text = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .failure(Refusal(reason: "no URL")) }
        guard let scheme = scheme(of: text) else {
            if text.hasPrefix("/") {
                return .failure(Refusal(reason: "a path in the sandbox is relative to the tab's messages, not absolute"))
            }
            guard NativeShowPolicy.isRelativePath(text) else {
                return .failure(Refusal(reason: "a path in the sandbox stays in the folder of the tab's messages"))
            }
            return .success(.sandboxFile(text))
        }
        switch scheme {
        case "http", "https":
            guard let parsed = URL(string: text), let host = parsed.host, !host.isEmpty else {
                return .failure(Refusal(reason: "not a valid URL"))
            }
            return .success(.sandboxFetch(parsed))
        case "data":
            return inline(text, kind: kind)
        default:
            return .failure(Refusal(reason: "\(scheme): URLs do not load here: use https, http, data:, or a path in the sandbox"))
        }
    }

    /// The URL scheme, lowercased, or nil when `text` is a path.
    static func scheme(of text: String) -> String? {
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let candidate = text[text.startIndex..<colon]
        guard let first = candidate.first, first.isASCII, first.isLetter,
              // A colon after a slash belongs to a path (`notes/12:30.png`).
              candidate.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+-.".contains($0)) }) else { return nil }
        return candidate.lowercased()
    }

    /// `data:[<mime>][;param...][;base64],<payload>`.
    static func inline(_ text: String, kind: Kind) -> Result<Source, Refusal> {
        guard let comma = text.firstIndex(of: ",") else { return .failure(Refusal(reason: "a data: URL without a comma")) }
        let header = text[text.index(text.startIndex, offsetBy: "data:".count)..<comma].split(separator: ";").map(String.init)
        let payload = String(text[text.index(after: comma)...])
        let mime = (header.first ?? "").lowercased()
        guard accepts(mime, for: kind) else {
            return .failure(Refusal(reason: "a data: URL of \(mime.isEmpty ? "no type" : mime), not \(kind.rawValue)/*"))
        }
        let data: Data?
        if header.dropFirst().contains(where: { $0.lowercased() == "base64" }) {
            data = Data(base64Encoded: payload, options: .ignoreUnknownCharacters)
        } else {
            data = payload.removingPercentEncoding.map { Data($0.utf8) }
        }
        guard let data, !data.isEmpty else { return .failure(Refusal(reason: "the data: URL does not decode")) }
        guard data.count <= maxBytes else { return .failure(Refusal(reason: "over \(maxBytes / 1024 / 1024) MB")) }
        return .success(.inline(mimeType: mime, data: data))
    }

    /// Whether bytes of `mimeType` (parameters allowed) may show as `kind`.
    public static func accepts(_ mimeType: String, for kind: Kind) -> Bool {
        let base = mimeType.split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
        let parts = base.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 2 && parts[0] == kind.rawValue && !parts[1].isEmpty
    }

    /// The MIME type of a media file in the sandbox, by its extension.
    public static func mimeType(forPath path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "mp4", "m4v": "video/mp4"
        case "mov": "video/quicktime"
        case "webm": "video/webm"
        case "mp3": "audio/mpeg"
        case "m4a": "audio/mp4"
        case "aac": "audio/aac"
        case "wav": "audio/wav"
        case "ogg", "oga": "audio/ogg"
        case "flac": "audio/flac"
        case "heic": "image/heic"
        case "avif": "image/avif"
        case "tif", "tiff": "image/tiff"
        case "bmp": "image/bmp"
        default: NativeShowPolicy.mimeType(for: path)
        }
    }

    /// The bytes of a sandbox fetch: `paddock --fetch` prints the response's Content-Type, a
    /// newline, and the body as base64. Refused when the type is not `kind`'s or it is too large.
    public static func decodeFetched(_ output: Data, kind: Kind) -> Result<(mimeType: String, data: Data), Refusal> {
        guard output.count <= A2UICommands.base64Length(maxBytes) + 256 else {
            return .failure(Refusal(reason: "over \(maxBytes / 1024 / 1024) MB"))
        }
        guard let newline = output.firstIndex(of: 0x0A) else { return .failure(Refusal(reason: "the sandbox answered nothing")) }
        let mime = String(decoding: output[output.startIndex..<newline], as: UTF8.self).trimmingCharacters(in: .whitespaces)
        guard accepts(mime, for: kind) else {
            return .failure(Refusal(reason: "the server sent \(mime.isEmpty ? "no type" : mime), not \(kind.rawValue)/*"))
        }
        guard let data = Data(base64Encoded: output[(newline + 1)...], options: .ignoreUnknownCharacters), !data.isEmpty else {
            return .failure(Refusal(reason: "the sandbox's answer does not decode"))
        }
        guard data.count <= maxBytes else { return .failure(Refusal(reason: "over \(maxBytes / 1024 / 1024) MB")) }
        let base = mime.split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? mime
        return .success((base, data))
    }
}

import CryptoKit
import Foundation
import PaddockCore
import UniformTypeIdentifiers

/// A media file of a tab, on the Mac: where its bytes are, and their type.
struct A2UIMediaFile: Sendable, Equatable {
    let url: URL
    let mimeType: String
}

/// Loads a tab's Image, Video, and AudioPlayer bytes as `A2UIMedia` says (through the sandbox, or
/// from a `data:` URL), each URL once, into files in the tab's folder, where AVFoundation and
/// AppKit read them. Nothing here fetches from the network.
@MainActor
final class A2UIMediaStore {
    private let link: any A2UITabLink
    private let folder: URL
    private var loads: [Key: Task<Result<A2UIMediaFile, A2UIMedia.Refusal>, Never>] = [:]

    private struct Key: Hashable {
        let url: String
        let kind: A2UIMedia.Kind
    }

    init(link: any A2UITabLink, folder: URL) {
        self.link = link
        self.folder = folder
    }

    /// The file for `url` as `kind`, loaded once; a refusal says why it shows nothing.
    func load(_ url: String, kind: A2UIMedia.Kind) async -> Result<A2UIMediaFile, A2UIMedia.Refusal> {
        let key = Key(url: url, kind: kind)
        if let running = loads[key] { return await running.value }
        let task = Task { [link, folder] in await Self.fetch(url, kind: kind, link: link, folder: folder) }
        loads[key] = task
        return await task.value
    }

    func removeFiles() {
        for task in loads.values { task.cancel() }
        loads = [:]
        try? FileManager.default.removeItem(at: folder)
    }

    private nonisolated static func fetch(_ url: String, kind: A2UIMedia.Kind, link: any A2UITabLink, folder: URL) async -> Result<A2UIMediaFile, A2UIMedia.Refusal> {
        let bytes: (mimeType: String, data: Data)
        switch A2UIMedia.source(for: url, kind: kind) {
        case .failure(let refusal):
            return .failure(refusal)
        case .success(.inline(let mimeType, let data)):
            bytes = (mimeType, data)
        case .success(let source):
            do {
                bytes = try await link.media(source, kind: kind)
            } catch {
                return .failure(A2UIMedia.Refusal(reason: "the sandbox could not get it: \(error)"))
            }
        }
        // AVFoundation tells formats by the file's extension.
        let ext = UTType(mimeType: bytes.mimeType)?.preferredFilenameExtension ?? "bin"
        let digest = SHA256.hash(data: Data((kind.rawValue + "\n" + url).utf8)).map { String(format: "%02x", $0) }.joined()
        let file = folder.appendingPathComponent(String(digest.prefix(32))).appendingPathExtension(ext)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try bytes.data.write(to: file, options: .atomic)
        } catch {
            return .failure(A2UIMedia.Refusal(reason: "Paddock could not keep it: \(error.localizedDescription)"))
        }
        return .success(A2UIMediaFile(url: file, mimeType: bytes.mimeType))
    }
}

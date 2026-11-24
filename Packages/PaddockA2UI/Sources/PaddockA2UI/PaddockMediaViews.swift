import A2UICore
import AppKit
import AVKit
import PaddockCore
import SwiftUI

/// What a media view shows while its file loads, and when it cannot.
private struct MediaPlaceholder: View {
    let systemImage: String
    let reason: String?
    var minHeight: CGFloat = 120

    var body: some View {
        VStack(spacing: 6) {
            if let reason {
                Image(systemName: systemImage).font(.title).foregroundStyle(.secondary)
                Text(reason).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(3)
            } else {
                ProgressView()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .background(Color.gray.opacity(0.12), in: .rect(cornerRadius: 8))
    }
}

/// The basic catalog's Image, its bytes from `A2UIMediaStore`: `variant` sets the size and
/// `fit` how the picture fills it, as in A2UI's own Image.
struct PaddockImage: View {
    let node: Node
    let media: A2UIMediaStore
    @State private var loaded: Result<NSImage, A2UIMedia.Refusal>?

    private var url: String { node.string(for: "url") ?? "" }
    private var variant: String { node.string(for: "variant") ?? "mediumFeature" }
    private var label: String {
        let text = node.string(for: "description") ?? ""
        return text.isEmpty ? "Image" : text
    }

    var body: some View {
        Group {
            switch loaded {
            case .success(let image)?:
                sized(Image(nsImage: image))
            case .failure(let refusal)?:
                MediaPlaceholder(systemImage: "photo", reason: refusal.reason, minHeight: placeholderHeight)
            case nil:
                MediaPlaceholder(systemImage: "photo", reason: nil, minHeight: placeholderHeight)
            }
        }
        .accessibilityLabel(label)
        .task(id: url) {
            loaded = nil
            loaded = await media.load(url, kind: .image).flatMap { file -> Result<NSImage, A2UIMedia.Refusal> in
                guard let image = NSImage(contentsOf: file.url) else {
                    return .failure(A2UIMedia.Refusal(reason: "not a picture this Mac can show"))
                }
                return .success(image)
            }
        }
    }

    private var placeholderHeight: CGFloat {
        switch variant {
        case "icon": 24
        case "avatar": 40
        case "smallFeature": 100
        default: 160
        }
    }

    @ViewBuilder
    private func fitted(_ image: Image) -> some View {
        switch node.string(for: "fit") ?? (variant == "avatar" || variant == "header" ? "cover" : "fill") {
        case "contain", "scaleDown": image.resizable().scaledToFit()
        case "cover": image.resizable().scaledToFill()
        case "none": image
        default: image.resizable()
        }
    }

    @ViewBuilder
    private func sized(_ image: Image) -> some View {
        switch variant {
        case "icon":
            fitted(image).frame(width: 24, height: 24).clipped()
        case "avatar":
            fitted(image).frame(width: 40, height: 40).clipShape(Circle())
        case "smallFeature":
            image.resizable().scaledToFit().frame(maxWidth: 100, maxHeight: 100)
        case "largeFeature":
            image.resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 400)
        case "header":
            Color.clear.frame(height: 200).overlay { fitted(image) }.clipped()
        default:
            image.resizable().scaledToFit().frame(maxWidth: .infinity)
        }
    }
}

/// AVKit's player view aborts inside a headless test runner (as A2UI's own Video notes).
private let canHostPlayerView: Bool = {
    let process = ProcessInfo.processInfo
    return process.environment["XCTestConfigurationFilePath"] == nil
        && process.environment["XCTestBundlePath"] == nil
        && !process.processName.contains("xctest")
        && !process.processName.contains("testing-helper")
}()

/// An AVPlayer for a file the store loaded, or why there is none.
private struct LoadedPlayer {
    var player: AVPlayer?
    var refusal: A2UIMedia.Refusal?
}

/// The basic catalog's Video: the file from `A2UIMediaStore`, in AVKit's player; a poster, when
/// there is one, until the operator plays it.
struct PaddockVideo: View {
    let node: Node
    let media: A2UIMediaStore
    @State private var loaded: LoadedPlayer?
    @State private var poster: NSImage?
    @State private var showsPoster = true

    private var url: String { node.string(for: "url") ?? "" }
    private var posterURL: String? { node.string(for: "posterUrl") }

    var body: some View {
        Group {
            if let player = loaded?.player {
                ZStack {
                    if canHostPlayerView {
                        VideoPlayer(player: player).frame(minHeight: 220).clipShape(.rect(cornerRadius: 8))
                    } else {
                        Color.black.frame(minHeight: 220)
                    }
                    if showsPoster, let poster {
                        Button {
                            showsPoster = false
                            player.play()
                        } label: {
                            ZStack {
                                Image(nsImage: poster).resizable().scaledToFill()
                                Image(systemName: "play.circle.fill").font(.system(size: 48)).foregroundStyle(.white).shadow(radius: 4)
                            }
                            .frame(maxWidth: .infinity, minHeight: 220)
                            .clipShape(.rect(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Play video")
                    }
                }
            } else {
                MediaPlaceholder(systemImage: "video.slash", reason: loaded?.refusal?.reason, minHeight: 220)
            }
        }
        .task(id: url) {
            loaded?.player?.pause()
            loaded = nil
            showsPoster = true
            switch await media.load(url, kind: .video) {
            case .success(let file): loaded = LoadedPlayer(player: AVPlayer(url: file.url))
            case .failure(let refusal): loaded = LoadedPlayer(refusal: refusal)
            }
        }
        .task(id: posterURL) {
            poster = nil
            guard let posterURL, case .success(let file) = await media.load(posterURL, kind: .image) else { return }
            poster = NSImage(contentsOf: file.url)
        }
        .onDisappear { loaded?.player?.pause() }
    }
}

/// The basic catalog's AudioPlayer: its description, and AVKit's controls for the file from
/// `A2UIMediaStore`.
struct PaddockAudio: View {
    let node: Node
    let media: A2UIMediaStore
    @State private var loaded: LoadedPlayer?

    private var url: String { node.string(for: "url") ?? "" }
    private var text: String { node.string(for: "description") ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !text.isEmpty {
                Text(text).font(.subheadline.weight(.semibold)).lineLimit(1)
            }
            if let player = loaded?.player {
                if canHostPlayerView {
                    VideoPlayer(player: player).frame(height: 44)
                } else {
                    Color.gray.opacity(0.2).frame(height: 44)
                }
            } else {
                MediaPlaceholder(systemImage: "speaker.slash", reason: loaded?.refusal?.reason, minHeight: 44)
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.12), in: .rect(cornerRadius: 10))
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(text.isEmpty ? "Audio" : text)
        .task(id: url) {
            loaded?.player?.pause()
            loaded = nil
            switch await media.load(url, kind: .audio) {
            case .success(let file): loaded = LoadedPlayer(player: AVPlayer(url: file.url))
            case .failure(let refusal): loaded = LoadedPlayer(refusal: refusal)
            }
        }
        .onDisappear { loaded?.player?.pause() }
    }
}

@preconcurrency import AVFoundation
import PaddockCore
import PaddockShellCore
import Speech
import SwiftUI

// Voice for agents (backlog doc Voice): the Mac listens and speaks, only text crosses into and out of
// a sandbox. The rules (cleaning, the queue, checks of what the kit sends) live in PaddockCore.

// MARK: - Audio

/// The audio engine voice uses while the microphone is on (backlog doc Voice, Echo cancellation):
/// the microphone with Apple's voice processing, and a player for speech on the same engine, so the
/// speech is taken out of what the microphone hears and the operator can talk over an agent. It
/// runs only while something uses it (`acquire`, `release`).
@MainActor
final class VoiceAudio {
    enum Problem: Error, CustomStringConvertible {
        case noFormat

        var description: String { "no audio format for speech" }
    }

    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    /// Speech on its way to the player; the mixer converts it for the device.
    static let speechFormat = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)
    /// Voice processing is on: speech played through `player` is taken out of the microphone.
    /// Off when this Mac's audio setup refuses it; the microphone then works without it.
    private(set) var echoCancelling = false
    /// Told once when voice processing could not start.
    var onProblem: ((String) -> Void)?
    private var users = 0
    private var prepared = false

    func acquire() throws {
        if !prepared {
            guard let format = Self.speechFormat else { throw Problem.noFormat }
            do {
                try engine.inputNode.setVoiceProcessingEnabled(true)
                // Other apps' sound stays as loud as it was.
                engine.inputNode.voiceProcessingOtherAudioDuckingConfiguration =
                    AVAudioVoiceProcessingOtherAudioDuckingConfiguration(enableAdvancedDucking: false, duckingLevel: .min)
                // Voice processing needs the output's client format to be the microphone's
                // ("client-side input and output formats do not match", -10875, otherwise).
                engine.connect(engine.mainMixerNode, to: engine.outputNode, format: engine.inputNode.outputFormat(forBus: 0))
                echoCancelling = true
            } catch {
                onProblem?("No echo cancellation (voice processing is off): \(error)")
            }
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            prepared = true
        }
        if !engine.isRunning {
            engine.prepare()
            do {
                try engine.start()
            } catch where echoCancelling {
                // Some audio setups refuse voice processing: listen without it rather than not at all.
                onProblem?("No echo cancellation (voice processing would not start): \(error)")
                try? engine.inputNode.setVoiceProcessingEnabled(false)
                engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
                echoCancelling = false
                engine.prepare()
                try engine.start()
            }
        }
        users += 1
    }

    func release() {
        users = max(0, users - 1)
        if users == 0 {
            player.stop()
            engine.stop()
        }
    }
}

/// Waiting music on `VoiceAudio`'s engine (backlog doc Voice, Waiting music), so echo cancellation
/// takes it out of what the microphone hears while hands-free waits for a start word. Only with
/// echo cancellation: without it the recognizer would hear the music.
@MainActor
final class WaitingMusicPlayer {
    private let audio: VoiceAudio
    private var node: AVAudioSourceNode?
    private var renderer: WaitingMusicRenderer?
    private var ending: Task<Void, Never>?

    init(audio: VoiceAudio) {
        self.audio = audio
    }

    var isPlaying: Bool { renderer != nil }

    /// Starts (fading in) or stops (fading out) the music; the same again changes nothing.
    func play(_ on: Bool) {
        if on, renderer == nil {
            start()
        } else if !on, let renderer {
            renderer.stop()
            self.renderer = nil
            let node = node
            self.node = nil
            ending = Task {
                try? await Task.sleep(for: .seconds(WaitingMusicRenderer.fadeOut + 0.2))
                if let node {
                    audio.engine.detach(node)
                    audio.release()
                }
            }
        }
    }

    private func start() {
        guard (try? audio.acquire()) != nil else { return }
        guard audio.echoCancelling, let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1) else {
            audio.release()
            return
        }
        let renderer = WaitingMusicRenderer(sampleRate: format.sampleRate)
        let node = Self.source(renderer, format: format)
        audio.engine.attach(node)
        audio.engine.connect(node, to: audio.engine.mainMixerNode, format: format)
        self.renderer = renderer
        self.node = node
    }

    /// Not on the main actor: the render block runs on the audio thread.
    private nonisolated static func source(_ renderer: WaitingMusicRenderer, format: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { isSilence, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard let data = buffers.first?.mData else { return noErr }
            let samples = UnsafeMutableBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: Int(frameCount))
            if !renderer.render(into: samples) { isSilence.pointee = true }
            return noErr
        }
    }
}

// MARK: - Speaking

/// `SpeechQueue`'s synthesizer: AVSpeechSynthesizer with the voice `VoiceModel` picks (the system's
/// when nil). With `throughEngine` (the microphone is on) the speech is rendered to buffers and
/// played through `VoiceAudio`, whose echo cancellation then takes it out of the microphone;
/// otherwise AVSpeechSynthesizer plays it itself and the microphone stays off. One utterance at a
/// time (the queue makes sure), so one continuation is enough.
@MainActor
final class SystemSpeech: NSObject, SpeechSynthesizing, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let audio: VoiceAudio
    private var finished: CheckedContinuation<Bool, Never>?
    /// The utterance AVSpeechSynthesizer plays itself; its delegate calls are for it only.
    private var playing: ObjectIdentifier?
    private var writing = false
    var voiceIdentifier: String?
    /// The next utterances go through `audio`.
    var throughEngine = false

    init(audio: VoiceAudio) {
        self.audio = audio
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) async -> Bool {
        // Plain text: never SSML or attributed markup from a sandbox.
        let utterance = AVSpeechUtterance(string: text)
        if let voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = voice
        }
        if throughEngine, let format = VoiceAudio.speechFormat {
            do {
                try audio.acquire()
            } catch {
                return await play(utterance)
            }
            // Without echo cancellation the engine is no better than the synthesizer itself.
            guard audio.echoCancelling else {
                audio.release()
                return await play(utterance)
            }
            let done = await render(utterance, format: format)
            audio.release()
            return done
        }
        return await play(utterance)
    }

    private func play(_ utterance: AVSpeechUtterance) async -> Bool {
        await withCheckedContinuation { continuation in
            finish(false)
            finished = continuation
            playing = ObjectIdentifier(utterance)
            synthesizer.speak(utterance)
        }
    }

    private func render(_ utterance: AVSpeechUtterance, format: AVAudioFormat) async -> Bool {
        await withCheckedContinuation { continuation in
            finish(false)
            finished = continuation
            writing = true
            let feed = SpeechFeed(player: audio.player, format: format) { [weak self] done in
                Task { @MainActor in self?.finishWriting(done) }
            }
            audio.player.play()
            synthesizer.write(utterance) { buffer in feed.add(buffer) }
        }
    }

    func stop() async {
        synthesizer.stopSpeaking(at: .immediate)
        if writing {
            audio.player.stop()
            finishWriting(false)
        }
    }

    private func finishWriting(_ done: Bool) {
        guard writing else { return }
        writing = false
        finish(done)
    }

    private func finish(_ done: Bool) {
        playing = nil
        finished?.resume(returning: done)
        finished = nil
    }

    // The delegate may be called on another thread, and for written utterances too: only the one
    // AVSpeechSynthesizer plays itself counts.
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in if self.playing == id { self.finish(true) } }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in if self.playing == id { self.finish(false) } }
    }
}

/// Speech rendered by AVSpeechSynthesizer.write, onto the player: each buffer converted to the
/// player's format and scheduled; done once the last one has played (an empty buffer ends it).
/// Called on the synthesizer's thread; the lock keeps the counts.
private final class SpeechFeed: @unchecked Sendable {
    private let lock = NSLock()
    private let player: AVAudioPlayerNode
    private let format: AVAudioFormat
    private let done: @Sendable (Bool) -> Void
    private var converter: AVAudioConverter?
    private var scheduled = 0
    private var ended = false
    private var reported = false

    init(player: AVAudioPlayerNode, format: AVAudioFormat, done: @escaping @Sendable (Bool) -> Void) {
        self.player = player
        self.format = format
        self.done = done
    }

    func add(_ buffer: AVAudioBuffer) {
        guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else {
            end()
            return
        }
        let converter = lock.withLock { () -> AVAudioConverter? in
            if self.converter == nil, pcm.format != format {
                self.converter = AVAudioConverter(from: pcm.format, to: format)
            }
            return self.converter
        }
        guard let output = convertAudio(pcm, with: converter, to: format) else { return }
        lock.withLock { scheduled += 1 }
        player.scheduleBuffer(output, completionCallbackType: .dataPlayedBack) { [self] _ in played() }
    }

    private func end() {
        let finished = lock.withLock { () -> Bool in
            ended = true
            return report()
        }
        if finished { done(true) }
    }

    private func played() {
        let finished = lock.withLock { () -> Bool in
            scheduled -= 1
            return report()
        }
        if finished { done(true) }
    }

    /// Under the lock: true once, when everything was written and played.
    private func report() -> Bool {
        guard ended, scheduled <= 0, !reported else { return false }
        reported = true
        return true
    }
}

/// The first channel of a float buffer, as a buffer of its own in `mono`.
private func firstChannel(of buffer: AVAudioPCMBuffer, as mono: AVAudioFormat) -> AVAudioPCMBuffer? {
    guard let source = buffer.floatChannelData?[0],
          let output = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: buffer.frameLength),
          let target = output.floatChannelData?[0] else { return nil }
    target.update(from: source, count: Int(buffer.frameLength))
    output.frameLength = buffer.frameLength
    return output
}

/// A buffer in another format, through `converter` (nil when the formats match).
private func convertAudio(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter?,
                          to format: AVAudioFormat) -> AVAudioPCMBuffer? {
    guard let converter else { return buffer }
    let ratio = format.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
    guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
    let pending = PendingBuffer(buffer)
    var error: NSError?
    converter.convert(to: output, error: &error) { _, status in
        guard let next = pending.take() else {
            status.pointee = .noDataNow
            return nil
        }
        status.pointee = .haveData
        return next
    }
    return error == nil ? output : nil
}

// MARK: - Listening

/// The operator's speech as text, on the Mac only: SpeechAnalyzer with SpeechTranscriber (macOS 26),
/// on-device, with the project's words as contextual strings. Nothing is recorded or kept.
@MainActor
@Observable
final class SpeechListener {
    enum Problem: Error, CustomStringConvertible {
        case microphoneDenied
        case unsupportedLanguage
        /// The language's model is not on this Mac; macOS downloads it once the operator agrees.
        case needsDownload
        case noAudioFormat
        case noConversion(String)

        var description: String {
            switch self {
            case .microphoneDenied: "Paddock may not use the microphone (System Settings, Privacy & Security, Microphone)"
            case .unsupportedLanguage: "Speech recognition does not support this Mac's language"
            case .needsDownload: "The speech model for this language is not downloaded yet"
            case .noAudioFormat: "Speech recognition found no audio format it can use"
            case .noConversion(let formats): "Cannot convert the microphone's audio for speech recognition: \(formats)"
            }
        }
    }

    /// What was recognized so far, final and tentative parts together.
    private(set) var text = ""
    private(set) var isListening = false
    private var finalized = ""
    private let audio: VoiceAudio
    /// The tap is on `audio`'s microphone.
    private var tapped = false
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var results: Task<Void, Never>?
    /// Called when the text changes, and when "stop" or "send" was said on its own
    /// (`DictationCommand`; dropped from the text).
    @ObservationIgnored var onHeard: (() -> Void)?
    @ObservationIgnored var onCommand: ((DictationCommand) -> Void)?
    /// Every result as it comes, tentative ones too, before commands are taken out.
    @ObservationIgnored var onResult: ((String) -> Void)?
    /// Whether a final result is kept; nil keeps all. Hands-free drops what was said before its
    /// start word, so a long wait does not pile up the room's talk.
    @ObservationIgnored var keepsFinal: ((String) -> Bool)?
    /// Called while the microphone hears speech (`VoiceActivity`), a few times a second at most:
    /// ahead of the text, which comes later.
    @ObservationIgnored var onSpeech: (() -> Void)?

    init(audio: VoiceAudio) {
        self.audio = audio
    }

    private static func transcriber() async throws -> SpeechTranscriber {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) else {
            throw Problem.unsupportedLanguage
        }
        return SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults],
                                 attributeOptions: [])
    }

    /// Whether the language's model still has to be downloaded.
    static func needsDownload() async -> Bool {
        guard let transcriber = try? await transcriber() else { return false }
        return await AssetInventory.status(forModules: [transcriber]) != .installed
    }

    /// Downloads the language's model through macOS (`AssetInventory`), after the operator agreed.
    static func download() async throws {
        let transcriber = try await transcriber()
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }

    func start(words: [String]) async throws {
        guard !isListening else { return }
        guard await AVAudioApplication.requestRecordPermission() else { throw Problem.microphoneDenied }
        let transcriber = try await Self.transcriber()
        guard await AssetInventory.status(forModules: [transcriber]) == .installed else { throw Problem.needsDownload }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        if !words.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = words
            try await analyzer.setContext(context)
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw Problem.noAudioFormat
        }
        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        try await analyzer.start(inputSequence: stream)
        text = ""
        finalized = ""
        results = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    self?.received(String(result.text.characters), isFinal: result.isFinal)
                }
            } catch {
                // Ends with the input; a failure leaves what was recognized.
            }
        }
        let activity = SpeechActivity { [weak self] in
            Task { @MainActor in self?.onSpeech?() }
        }
        // The shared engine, with echo cancellation, so speech played meanwhile is not heard.
        try audio.acquire()
        do {
            try Self.tap(audio.engine.inputNode, to: format, into: continuation, activity: activity)
        } catch {
            audio.release()
            throw error
        }
        tapped = true
        self.analyzer = analyzer
        input = continuation
        isListening = true
    }

    /// Stops listening and returns everything recognized.
    func stop() async -> String {
        guard isListening else { return text }
        if tapped {
            audio.engine.inputNode.removeTap(onBus: 0)
            audio.release()
            tapped = false
        }
        input?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await results?.value
        analyzer = nil
        input = nil
        results = nil
        isListening = false
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func received(_ part: String, isFinal: Bool) {
        onResult?(part)
        let (part, commands) = DictationCommand.strip(part)
        if isFinal {
            if keepsFinal?(part) ?? true { finalized += part }
            text = finalized
        } else {
            text = finalized + part
        }
        onHeard?()
        // Once, on the final result (the last one said wins); a tentative one only stays out of the text.
        if isFinal, let command = commands.last { onCommand?(command) }
    }

    /// The microphone's buffers converted to the analyzer's format. Not on the main actor: the tap
    /// runs on the audio thread.
    private nonisolated static func tap(_ node: AVAudioInputNode, to format: AVAudioFormat,
                                        into input: AsyncStream<AnalyzerInput>.Continuation,
                                        activity: SpeechActivity) throws {
        let source = node.outputFormat(forBus: 0)
        // Voice processing can give the microphone many channels with the voice in the first: that
        // channel alone, then converted (a converter from many channels may not exist at all).
        let mono = source.channelCount > 1 ? AVAudioFormat(standardFormatWithSampleRate: source.sampleRate, channels: 1) : nil
        let converted = mono ?? source
        let converter: AVAudioConverter?
        if converted == format {
            converter = nil
        } else if let made = AVAudioConverter(from: converted, to: format) {
            converter = made
        } else {
            throw Problem.noConversion("\(converted) to \(format)")
        }
        node.installTap(onBus: 0, bufferSize: 4096, format: source) { buffer, _ in
            guard let buffer = mono.map({ firstChannel(of: buffer, as: $0) }) ?? buffer else { return }
            activity.hear(buffer)
            guard let output = convertAudio(buffer, with: converter, to: format) else { return }
            input.yield(AnalyzerInput(buffer: output))
        }
    }

    /// The microphone's format and whether voice processing is on, for the log.
    func describeInput() -> String {
        "\(audio.engine.inputNode.outputFormat(forBus: 0)), echo cancellation \(audio.echoCancelling ? "on" : "off")"
    }
}

/// Speech in the microphone's buffers, on the audio thread (`VoiceActivity`): reports it at most
/// every quarter second. Only the tap calls `hear`, one buffer at a time; the lock keeps it safe anyway.
private final class SpeechActivity: @unchecked Sendable {
    private let lock = NSLock()
    private var activity = VoiceActivity()
    private var reported = Date.distantPast
    private let report: @Sendable () -> Void

    init(report: @escaping @Sendable () -> Void) {
        self.report = report
    }

    func hear(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let level = VoiceActivity.level(of: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        let now = Date()
        let due = lock.withLock { () -> Bool in
            guard activity.isSpeech(level: level), now.timeIntervalSince(reported) >= 0.25 else { return false }
            reported = now
            return true
        }
        if due { report() }
    }
}

/// The one buffer a conversion is given. The converter calls its input block synchronously, on the
/// calling thread, so nothing else touches it.
private final class PendingBuffer: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }

    func take() -> AVAudioPCMBuffer? {
        defer { buffer = nil }
        return buffer
    }
}

// MARK: - The model

/// Everything voice in the app: following each voice sandbox's `paddock-voice-watch`, speaking what
/// agents say, their questions, and dictation into agent tabs.
@MainActor
@Observable
final class VoiceModel {
    /// A question an agent asked (`paddock-voice ask`), shown under its terminal until answered.
    struct Ask: Identifiable, Equatable {
        let id: String
        let project: String
        let tab: UUID?
        let question: String
        let choices: [String]
        let deadline: Date
    }

    /// What dictation is for: a tab's prompt, or the answer to a question.
    enum Target: Equatable {
        case tab(project: String, tab: UUID)
        case ask(Ask)
    }

    weak var app: AppModel?
    private let audio: VoiceAudio
    private let music: WaitingMusicPlayer
    private var musicFollower: Task<Void, Never>?
    let listener: SpeechListener
    private let speech: SystemSpeech
    private let queue: SpeechQueue
    private var watchers: [String: Task<Void, Never>] = [:]
    private(set) var asks: [Ask] = []
    /// Each project's words from its agent (`paddock-voice words`).
    private(set) var agentWords: [String: [String]] = [:]
    /// The open dictation: from the first click on the microphone until Cancel or Send.
    private(set) var recording: Target?
    /// What was heard in the open dictation before its last pause; the operator may edit it while paused.
    var draft = ""
    /// The microphone is on (or turning on) for the open dictation.
    private(set) var listening = false
    private var starting: Task<Void, Never>?
    private var stopping: Task<Void, Never>?
    /// Terminal tabs whose voice popup is open: from the microphone's click or a question until
    /// the operator closes it. Sending or answering leaves it open.
    private(set) var shownPanels: Set<UUID> = []

    func isPanelShown(_ terminal: UUID) -> Bool { shownPanels.contains(terminal) }

    func showPanel(_ terminal: UUID) { shownPanels.insert(terminal) }

    /// Closes the popup, dropping what its dictation heard without sending it.
    func closePanel(_ terminal: UUID, targets: [Target]) {
        shownPanels.remove(terminal)
        if let recording, targets.contains(recording) { cancelRecording() }
    }

    /// The agent tab in front, for Option-Space.
    private(set) var focused: (project: String, tab: UUID)?
    /// Tabs whose agent got the voice settings (`--set-status`), with their project.
    private var told: [UUID: String] = [:]
    /// Asked the operator before macOS downloads the speech model.
    var asksForDownload = false
    private var keyMonitor: Any?
    private var voicesObserver: Any?

    init() {
        let audio = VoiceAudio()
        self.audio = audio
        music = WaitingMusicPlayer(audio: audio)
        listener = SpeechListener(audio: audio)
        let speech = SystemSpeech(audio: audio)
        self.speech = speech
        queue = SpeechQueue(synthesizer: speech)
        audio.onProblem = { [weak self] problem in self?.app?.appendLog(problem, category: .voice, isError: true) }
        reloadVoices()
        // A voice downloaded in System Settings shows up without a restart.
        voicesObserver = NotificationCenter.default.addObserver(
            forName: AVSpeechSynthesizer.availableVoicesDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.voicesChanged() }
        }
        // Hands-free ends when Paddock goes to the background, unless the operator keeps it.
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkHandsFreeLimits(appActive: false) }
        }
    }

    // MARK: Voices

    /// The Mac's voices, without novelty ones.
    private(set) var installedVoices: [SpeechVoice] = []
    /// The voice the operator chose (the microphone's right-click menu); nil is automatic, the best
    /// for the Mac's language (`SpeechVoices.pick`).
    var chosenVoice = UserDefaults.standard.string(forKey: "voiceIdentifier") {
        didSet {
            UserDefaults.standard.set(chosenVoice, forKey: "voiceIdentifier")
            applyVoice()
        }
    }
    /// The operator closed the hint about better voices.
    var voiceHintDismissed = UserDefaults.standard.bool(forKey: "voiceHintDismissed") {
        didSet { UserDefaults.standard.set(voiceHintDismissed, forKey: "voiceHintDismissed") }
    }

    /// The Mac's language, read once.
    private let language = AVSpeechSynthesisVoice.currentLanguageCode()

    /// The voices for the Mac's language, best first; worked out when the list changes, not per view update.
    private(set) var offeredVoices: [SpeechVoice] = []
    /// The voice Automatic picks.
    var automaticVoice: SpeechVoice? { offeredVoices.first }
    /// Only basic voices for the language: worth a hint where to get a better one.
    var suggestsBetterVoice: Bool { (offeredVoices.first?.quality ?? .basic) == .basic }

    private var voicesLoading: Task<Void, Never>?
    private var voicesRead = Date.distantPast

    /// Reading the voices can be slow and may itself announce a change, so it runs off the main
    /// thread, one read at a time, and a change notice right after a read is left alone.
    private func voicesChanged() {
        guard Date().timeIntervalSince(voicesRead) > 5 else { return }
        reloadVoices()
    }

    private func reloadVoices() {
        guard voicesLoading == nil else { return }
        voicesLoading = Task {
            let voices = await Task.detached(priority: .utility) { Self.readVoices() }.value
            voicesRead = Date()
            voicesLoading = nil
            guard voices != installedVoices || offeredVoices.isEmpty else { return }
            installedVoices = voices
            offeredVoices = SpeechVoices.offered(voices, language: language)
            applyVoice()
        }
    }

    private nonisolated static func readVoices() -> [SpeechVoice] {
        AVSpeechSynthesisVoice.speechVoices().map { voice in
            let quality: SpeechVoice.Quality = switch voice.quality {
            case .premium: .premium
            case .enhanced: .enhanced
            case .default: .basic
            @unknown default: .basic
            }
            return SpeechVoice(id: voice.identifier, name: voice.name, language: voice.language, quality: quality,
                               isNovelty: voice.voiceTraits.contains(.isNoveltyVoice))
        }
    }

    private func applyVoice() {
        speech.voiceIdentifier = SpeechVoices.pick(installedVoices, language: language, chosen: chosenVoice)?.id
    }

    /// Where macOS downloads better voices: System Settings, Accessibility (then Spoken Content,
    /// System voice, Manage Voices).
    func openVoiceSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Nothing is spoken while muted, and agents count voice reply as off.
    var muted: Bool {
        get { UserDefaults.standard.bool(forKey: "voiceMuted") }
        set { UserDefaults.standard.set(newValue, forKey: "voiceMuted") }
    }

    /// Hands-free: a dictation is sent on its own `handsFreeDelay` after the operator stops talking,
    /// and a question an agent asks is listened for once it was read out (`listenHandsFree`). Saying "stop" on its own, pausing, or editing the text stops that for the
    /// dictation.
    ///
    /// Only the operator turns it on, and it is not remembered across launches: it ends by itself
    /// after `handsFreeIdleMinutes` without the operator speaking, and when Paddock goes to the
    /// background unless `keepHandsFreeInBackground` (`HandsFreeLimits`).
    var handsFree = false {
        didSet {
            // Hands-free is a spoken back-and-forth, so the agents reply by voice too. Turning it
            // off leaves voice reply as it is.
            if handsFree && !voiceReply { voiceReply = true }
            if handsFree {
                listenTurnedOff = false
                operatorLastActive = Date()
                startLimitWatch()
                arm()
            } else {
                limitWatch?.cancel()
                limitWatch = nil
                disarm()
            }
        }
    }

    /// Minutes without the operator speaking after which hands-free turns itself off; 0 is never.
    var handsFreeIdleMinutes = UserDefaults.standard.object(forKey: "voiceHandsFreeIdleMinutes") as? Int
        ?? HandsFreeLimits.defaultIdleMinutes {
        didSet { UserDefaults.standard.set(handsFreeIdleMinutes, forKey: "voiceHandsFreeIdleMinutes") }
    }

    /// Keep hands-free on while Paddock is in the background (off by default).
    var keepHandsFreeInBackground = UserDefaults.standard.bool(forKey: "voiceHandsFreeKeepInBackground") {
        didSet { UserDefaults.standard.set(keepHandsFreeInBackground, forKey: "voiceHandsFreeKeepInBackground") }
    }

    private var handsFreeLimits: HandsFreeLimits {
        HandsFreeLimits(idleMinutes: handsFreeIdleMinutes, keepInBackground: keepHandsFreeInBackground)
    }

    /// When hands-free was turned on, or the operator last spoke or used Listen.
    private var operatorLastActive = Date()
    private var limitWatch: Task<Void, Never>?
    private var activeObserver: Any?

    /// Turns hands-free off, and says so in the Log, when a limit is reached.
    private func checkHandsFreeLimits(appActive: Bool) {
        let idleFor = Date().timeIntervalSince(operatorLastActive)
        guard handsFree, let reason = handsFreeLimits.reason(idleFor: idleFor, appActive: appActive) else { return }
        app?.appendLog(reason.message, category: .voice)
        handsFree = false
    }

    private func startLimitWatch() {
        limitWatch?.cancel()
        limitWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self, self.handsFree else { return }
                self.checkHandsFreeLimits(appActive: NSApp.isActive)
            }
        }
    }

    /// Voice reply: the agents end with a spoken summary (`paddock-voice say`) or ask by voice;
    /// off, they reply in the terminal as usual. The kit's prompt hook tells them with each prompt.
    var voiceReply = UserDefaults.standard.bool(forKey: "voiceReply") {
        didSet {
            UserDefaults.standard.set(voiceReply, forKey: "voiceReply")
            for (tab, project) in told { tell(project: project, tab: tab) }
        }
    }

    static let handsFreeDelay: Duration = .seconds(4)
    /// Quiet music while hands-free waits for an agent (`voiceWaitingMusic`, on by default; backlog
    /// doc Voice, Waiting music): after a send, while the microphone waits for a start word and the
    /// tab's agent reports working (the status kit), from `musicDelay` on. Not while muted.
    var waitingMusic = UserDefaults.standard.object(forKey: "voiceWaitingMusic") as? Bool ?? true {
        didSet { UserDefaults.standard.set(waitingMusic, forKey: "voiceWaitingMusic") }
    }
    /// A quick reply gets no music.
    static let musicDelay: TimeInterval = 3

    /// The operator turned Listen off (the pill, the microphone, or Option-Space): hands-free does
    /// not turn it on again by itself, after a reply, a send, or a question, until the operator
    /// listens again or turns hands-free on.
    private var listenTurnedOff = false

    /// Hands-free's start words (`voiceWakeWord` in the app's defaults, comma-separated, "Paddock,
    /// computer" when unset; an empty string turns them off): when hands-free opens the microphone
    /// into a tab on its own, nothing heard counts, and nothing is sent, until the operator says one
    /// (`WakeWords`). Clicking Listen, Option-Space, and answering a question need none.
    var wakeWord: WakeWords? {
        WakeWords(setting: UserDefaults.standard.string(forKey: "voiceWakeWord") ?? WakeWords.defaultSetting)
    }
    /// The start words the microphone waits for now, while it listens; nil when what it hears counts.
    private(set) var waitingFor: WakeWords?
    /// The start word was said in this listening.
    private(set) var wakeHeard = false
    /// Waiting for the start word: for the popup's hint.
    var awaitsWakeWord: Bool { listening && waitingFor != nil && !wakeHeard }
    /// When the open dictation is sent on its own; nil when it is not (hands-free off or stopped).
    private(set) var sendsAt: Date?
    /// Hands-free still applies to the open dictation.
    private var armed = false
    private var countdown: Task<Void, Never>?

    func isChosen(_ project: Project) -> Bool {
        guard let app else { return false }
        return VoiceKit.isChosen(by: project, app: app.appConfig)
    }

    func asks(for project: Project) -> [Ask] { asks.filter { $0.project == project.name } }

    // MARK: Watchers

    /// Starts or stops the watchers to match: a project with the voice kit whose sandbox runs.
    func sync() {
        guard let app, let sbxPath = app.sbxPath else { return }
        installKeyMonitor()
        let wanted = Set(app.projects.projects.filter { app.state(of: $0) == .running && isChosen($0) }.map(\.name))
        for (name, task) in watchers where !wanted.contains(name) {
            task.cancel()
            watchers[name] = nil
            asks.removeAll { $0.project == name }
        }
        for name in wanted where watchers[name] == nil {
            watchers[name] = watch(name, sbx: URL(fileURLWithPath: sbxPath))
        }
    }

    /// Follows the sandbox's `paddock-voice-watch`. The lines are untrusted (`VoiceMessage`). Started
    /// again after it ends, less often each time.
    private func watch(_ name: String, sbx: URL) -> Task<Void, Never> {
        Task { [weak self] in
            var delay: Duration = .seconds(2)
            while !Task.isCancelled {
                do {
                    for try await line in FoundationLineStreamer(holdsInputOpen: true)
                        .lines(sbx, arguments: VoiceKit.watchArguments(sandbox: name)) {
                        guard let self else { return }
                        self.receive(line, from: name)
                        delay = .seconds(2)
                    }
                } catch {
                    // A sandbox from before the kit has no watcher; nothing to say each time.
                }
                try? await Task.sleep(for: delay)
                delay = min(delay * 2, .seconds(60))
            }
        }
    }

    private func receive(_ line: String, from project: String) {
        guard let message = VoiceMessage(line: line) else { return }
        guard !message.isStale(now: Date()) else { return }
        // Everything an agent says or asks shows in the popup; it is read aloud only with voice reply on.
        switch message.kind {
        case .say(let text):
            record(.init(speaker: .agent, text: text, tab: message.tab), in: project)
            Task {
                // Read out first, so the microphone does not hear it.
                if aloud, await !speakWithoutListening(utterance(text, project: project, tab: message.tab)) { return }
                if let tab = message.tab { listenHandsFree(.tab(project: project, tab: tab)) }
            }
        case .ask(let question, let choices, let deadline):
            let ask = Ask(id: message.id, project: project, tab: message.tab, question: question, choices: choices, deadline: deadline)
            asks.removeAll { $0.id == ask.id }
            asks.append(ask)
            record(.init(speaker: .agent, text: question, isQuestion: true, tab: message.tab), in: project)
            Task {
                if aloud, await !speakWithoutListening(utterance(question, project: project, tab: message.tab)) { return }
                listenHandsFree(.ask(ask))
            }
        case .cancel:
            asks.removeAll { $0.id == message.id && $0.project == project }
            if case .ask(let ask) = recording, ask.id == message.id {
                cancelRecording()
            }
        case .words(let words):
            agentWords[project] = words
        }
    }

    /// Speaks without taking the Mac's voice for the operator's: a dictation listening now pauses
    /// (keeping what it heard, and not sending on its own meanwhile); hands-free listens again
    /// afterwards (`listenHandsFree`). Meanwhile, with hands-free on or a dictation that was
    /// listening, the microphone listens only for "stop" or "cancel" (`DictationCommand.stopsSpeech`:
    /// anywhere in a tentative result, since it comes mixed into the speech), which cuts the speech
    /// off and keeps the microphone off; everything else it hears is dropped. Returns false when
    /// cut off that way.
    @discardableResult
    private func speakWithoutListening(_ utterance: SpeechQueue.Utterance) async -> Bool {
        let wasListening = listening
        if listening {
            disarm()
            await stopListening()
        }
        let watches = (handsFree && !listenTurnedOff || wasListening) && !watchingForStop && NSApp.isActive
        cutOff = false
        cutByVoice = false
        if watches {
            watchingForStop = true
            listener.onHeard = nil
            listener.onSpeech = nil
            listener.onCommand = nil
            listener.keepsFinal = nil
            // Tentative results, as they come: the operator's word arrives mixed into the speech.
            listener.onResult = { [weak self] heard in
                guard let self else { return }
                self.heardWhileSpeaking = heard
                guard !self.cutOff, DictationCommand.stopsSpeech(heard: heard, spoken: utterance.text) else { return }
                self.cutOff = true
                self.chime(.stop)
                self.cutByVoice = true
                Task {
                    if let tab = utterance.tab { await self.queue.interrupt(tab: tab) } else { await self.queue.interruptAll() }
                }
            }
            do {
                try await listener.start(words: [])
                heardWhileSpeaking = ""
            } catch {
                watchingForStop = false
                app?.appendLog("Could not listen for \"stop\" while an agent speaks: \(error)", category: .voice,
                               source: logSource(project: utterance.project, tab: utterance.tab), isError: true)
            }
        }
        speaking += 1
        // With the microphone on, through the shared engine, whose echo cancellation takes the
        // speech out of what the microphone hears (`VoiceAudio`).
        speech.throughEngine = watchingForStop
        _ = await queue.speak(utterance)
        speech.throughEngine = false
        speaking -= 1
        // A dictation the operator started meanwhile took the listener over (`listen`).
        if watches, watchingForStop {
            watchingForStop = false
            listener.onResult = nil
            _ = await listener.stop()
            if heardWhileSpeaking?.isEmpty == true {
                app?.appendLog("Heard nothing while an agent spoke (listening for \"stop\")", category: .voice,
                               source: logSource(project: utterance.project, tab: utterance.tab))
            }
        }
        heardWhileSpeaking = nil
        // Said, not clicked: the microphone comes back shortly, for the paused dictation or the next reply.
        if cutByVoice {
            cutByVoice = false
            if let open = recording {
                resumeSoon(open)
            } else if handsFree, let tab = utterance.tab {
                resumeSoon(.tab(project: utterance.project, tab: tab))
            }
        }
        return !cutOff
    }

    /// Agents being read aloud now (more than one when several speak in turn).
    private var speaking = 0
    var isSpeaking: Bool { speaking > 0 }

    /// The popup's Cancel while an agent is read aloud: like saying "cancel", it stops the speech
    /// and the microphone stays off.
    func cancelSpeech() {
        cutOff = true
        resuming?.cancel()
        Task { await queue.interruptAll() }
    }

    /// What the microphone hears while an agent is read aloud and it listens for "stop": shown in
    /// the popup, so the operator can see it hears them. Nil while it does not listen that way.
    private(set) var heardWhileSpeaking: String?

    /// The listener is on only for "stop" while an agent is read aloud (`speakWithoutListening`).
    private var watchingForStop = false
    /// The operator said "stop" while an agent was read aloud.
    private var cutOff = false

    /// Plays the waiting music while this listening waits for a start word and the agent works;
    /// fades it out once either ends, and when the microphone goes off.
    private func followMusic() {
        musicFollower?.cancel()
        let since = Date()
        musicFollower = Task { [weak self] in
            while !Task.isCancelled, let self, self.listening {
                self.music.play(self.musicPlays(since: since))
                try? await Task.sleep(for: .milliseconds(500))
            }
            self?.music.play(false)
        }
    }

    private func musicPlays(since: Date) -> Bool {
        guard waitingMusic, !muted, awaitsWakeWord, Date().timeIntervalSince(since) >= Self.musicDelay,
              case .tab(let project, let tab) = recording else { return false }
        return app?.terminals[project]?.agents.activity(ofTab: tab) == .working
    }

    /// A short macOS sound when the microphone heard a start word or a spoken "stop", so the
    /// operator knows without looking. Not while muted.
    private enum Chime: String {
        case start = "Pop"
        case stop = "Bottle"
    }

    private func chime(_ chime: Chime) {
        guard !muted else { return }
        NSSound(named: NSSound.Name(chime.rawValue))?.play()
    }

    /// Agents are read aloud: voice reply on and not muted.
    private var aloud: Bool { voiceReply && !muted }

    /// Each project's back and forth, for its voice popups.
    private(set) var conversations: [String: VoiceConversation] = [:]

    private func record(_ entry: VoiceConversation.Entry, in project: String) {
        conversations[project, default: VoiceConversation()].append(entry)
    }

    /// What a popup over `tab` shows; `untabbed` for the left half's, which also takes the agents
    /// that run outside a tab Paddock opened.
    func conversation(for project: Project, tab: UUID?, untabbed: Bool) -> [VoiceConversation.Entry] {
        conversations[project.name]?.entries(for: tab, untabbed: untabbed) ?? []
    }

    private func utterance(_ text: String, project: String, tab: UUID?) -> SpeechQueue.Utterance {
        SpeechQueue.Utterance(project: project, tab: tab, text: text)
    }

    // MARK: Answers

    /// Answers a question from its banner: a choice, typed text, or Dismiss.
    func answer(_ ask: Ask, with answer: VoiceAnswer) {
        asks.removeAll { $0.id == ask.id }
        record(.init(speaker: .operator, text: VoiceConversation.text(of: answer), tab: ask.tab), in: ask.project)
        if case .ask(let open)? = recording, open.id == ask.id { cancelRecording() }
        self.answer(ask.id, in: ask.project, with: answer)
    }

    /// Hands-free keeps the conversation going and the microphone on: once an agent's say or
    /// question has been read out, and after each send, it listens for the next reply (into the
    /// tab, or as the answer), which goes `handsFreeDelay` after the operator stops talking. A
    /// dictation that already holds words is listened to again instead; an empty one follows the
    /// conversation to `target`. Only while Paddock is the app in front; the operator turned
    /// hands-free on.
    private func listenHandsFree(_ target: Target) {
        guard handsFree, !listenTurnedOff, !listening, stopping == nil, NSApp.isActive else { return }
        if let open = recording {
            guard open != target, DictationText.prompt(draft) == nil else {
                listen(open)
                return
            }
            recording = nil
        }
        switch target {
        case .ask(let ask):
            guard asks.contains(where: { $0.id == ask.id }) else { return }
        case .tab(let project, let tab):
            guard app?.terminals[project]?.sessions[tab] != nil else { return }
        }
        listen(target)
    }

    private func answer(_ id: String, in project: String, with answer: VoiceAnswer) {
        guard let arguments = VoiceKit.answerArguments(sandbox: project, id: id) else { return }
        Task {
            await run(arguments, stdin: Data(answer.line.utf8), what: "answer the agent in \(project)",
                      project: project)
        }
    }

    private func run(_ arguments: [String], stdin: Data, what: String, project: String, tab: UUID? = nil) async {
        guard let sbxPath = app?.sbxPath else { return }
        let source = logSource(project: project, tab: tab)
        do {
            let result = try await FoundationProcessRunner().run(URL(fileURLWithPath: sbxPath), arguments: arguments,
                                                                 environment: nil, stdin: stdin)
            if result.exitCode != 0 {
                app?.appendLog("Could not \(what): \(result.stderrText)", category: .voice, source: source,
                               isError: true)
            }
        } catch {
            app?.appendLog("Could not \(what): \(error)", category: .voice, source: source, isError: true)
        }
    }

    /// The Log's source for a project and, when there is one, its agent tab ("app · agent 2").
    func logSource(project: String, tab: UUID?) -> String {
        guard let tab, let title = app?.terminals[project]?.title(of: tab) else { return project }
        return "\(project) · \(title)"
    }

    // MARK: Dictation

    /// The agent tab in front of the operator; its agent hears once that voice is on.
    func focus(project: Project, tab: UUID?) {
        guard let tab, isChosen(project) else {
            if focused?.project == project.name { focused = nil }
            return
        }
        focused = (project.name, tab)
        if told[tab] == nil {
            told[tab] = project.name
            tell(project: project.name, tab: tab)
        }
    }

    private func tell(project: String, tab: UUID) {
        let settings = VoiceSettings(voice: !muted, voiceReply: voiceReply)
        Task { await run(VoiceKit.settingsArguments(sandbox: project, tab: tab), stdin: settings.json,
                         what: "tell the agent in \(project) whether voice is on", project: project, tab: tab) }
    }

    /// What the open dictation holds now: the draft, then what the microphone hears.
    var heard: String {
        guard listening || stopping != nil else { return draft }
        return Self.join(draft, counted(listener.text))
    }

    /// What of the microphone's text counts: after the start word when it waits for one. Once it
    /// was heard, what came before it is already dropped (`keepsFinal`), so a recognizer that
    /// later spells the word otherwise keeps the whole text.
    private func counted(_ text: String) -> String {
        guard let waitingFor else { return text }
        return waitingFor.after(text) ?? (wakeHeard ? text : "")
    }

    func isRecording(_ target: Target) -> Bool { recording == target }

    /// The open dictation's text as the operator edits it. Edits count only once the microphone is
    /// off (`startEditing` turns it off), so what is heard never overwrites them.
    var editableText: String {
        get { heard }
        set {
            guard !listening else { return }
            draft = newValue
        }
    }

    /// The operator clicked into the text: the microphone pauses and nothing is sent on its own.
    func startEditing() {
        disarm()
        if listening { pause() }
    }

    /// The microphone's click: opens the dictation and listens, pauses it, or listens again (what
    /// is heard then is added to the draft). Another dictation already open keeps it.
    func toggleListening(_ target: Target) {
        guard recording == nil || recording == target else { return }
        // A click decides: no coming back on by itself, and hands-free counts as usual.
        resuming?.cancel()
        holdUntilSpeech = false
        if listening {
            listenTurnedOff = true
            disarm()
            pause()
        } else {
            listenTurnedOff = false
            operatorLastActive = Date()
            listen(target, byOperator: true)
        }
    }

    /// Hands-free for the open dictation, while it listens: into a tab, or answering a question.
    private func arm() {
        guard handsFree, listening, recording != nil, !holdUntilSpeech else { return }
        armed = true
        heardChanged()
    }

    /// No sending on its own for the rest of this dictation.
    func disarm() {
        armed = false
        countdown?.cancel()
        countdown = nil
        sendsAt = nil
    }

    /// The operator is talking: hands-free waits `handsFreeDelay` from now.
    private func heardChanged() {
        if let waitingFor, !wakeHeard, waitingFor.after(listener.text) != nil {
            wakeHeard = true
            listener.keepsFinal = nil
            chime(.start)
        }
        // Talk in the room before the start word is not the operator.
        if waitingFor == nil || wakeHeard { operatorLastActive = Date() }
        restartCountdown()
    }

    /// The microphone hears speech: the text is still coming, so the countdown starts over.
    private func speechHeard() {
        if waitingFor == nil || wakeHeard { operatorLastActive = Date() }
        if holdUntilSpeech {
            holdUntilSpeech = false
            arm()
        }
        restartCountdown()
    }

    /// Hands-free sends `handsFreeDelay` after the last speech and the last new text, whichever is
    /// later; nothing is sent before there is text.
    private func restartCountdown() {
        guard armed, let target = recording else { return }
        countdown?.cancel()
        guard DictationText.prompt(heard) != nil else {
            sendsAt = nil
            return
        }
        sendsAt = Date().addingTimeInterval(TimeInterval(Self.handsFreeDelay.components.seconds))
        countdown = Task {
            try? await Task.sleep(for: Self.handsFreeDelay)
            guard !Task.isCancelled, armed, recording == target else { return }
            disarm()
            send()
        }
    }

    /// "stop" said on its own: no sending on its own (until the operator listens again), and the
    /// microphone pauses so the text can be checked.
    private func heardStop() {
        chime(.stop)
        disarm()
        pause()
        if let open = recording { resumeSoon(open) }
    }

    /// The operator said "stop" or "cancel" while an agent spoke.
    private var cutByVoice = false
    /// After a spoken "stop" or "cancel", the microphone listens again `resumeDelay` later; it does
    /// not send on its own until the operator speaks again (`holdUntilSpeech`).
    static let resumeDelay: Duration = .seconds(2)
    private var resuming: Task<Void, Never>?
    /// Hands-free waits for speech before it counts down to a send again.
    private var holdUntilSpeech = false

    private func resumeSoon(_ target: Target) {
        resuming?.cancel()
        resuming = Task {
            try? await Task.sleep(for: Self.resumeDelay)
            resuming = nil
            // Not over an agent being read aloud: that listens again by itself afterwards.
            guard !Task.isCancelled, !listenTurnedOff, !listening, !isSpeaking, recording == nil || recording == target else { return }
            holdUntilSpeech = true
            listen(target)
        }
    }

    /// `byOperator`: the operator clicked Listen or pressed Option-Space. Otherwise hands-free opened
    /// the microphone, and into a tab with nothing said yet it waits for the start word (`wakeWord`).
    private func listen(_ target: Target, byOperator: Bool = false) {
        guard let app, !listening else { return }
        if recording == nil { draft = "" }
        recording = target
        listening = true
        waitingFor = nil
        wakeHeard = false
        if !byOperator, case .tab = target, DictationText.prompt(draft) == nil,
           let wakeWord {
            waitingFor = wakeWord
            listener.keepsFinal = { wakeWord.after($0) != nil }
        } else {
            listener.keepsFinal = nil
        }
        listener.onHeard = { [weak self] in self?.heardChanged() }
        listener.onCommand = { [weak self] command in
            // "stop" and "send" count only once the start word was said.
            guard let self, self.waitingFor == nil || self.wakeHeard else { return }
            switch command {
            case .stop: self.heardStop()
            case .send: self.send()
            }
        }
        listener.onSpeech = { [weak self] in self?.speechHeard() }
        let project: String
        switch target {
        case .tab(let name, let tab):
            project = name
            Task { await queue.interrupt(tab: tab) }
        case .ask(let ask):
            project = ask.project
            if let tab = ask.tab { Task { await queue.interrupt(tab: tab) } }
        }
        let folder = app.project(named: project).map { URL(fileURLWithPath: $0.folder) }
        let words = (waitingFor?.phrases ?? [])
            + VoiceKeywords.combined(agent: agentWords[project] ?? [],
                                     project: folder.map { VoiceKeywords.projectNames(in: $0) } ?? [])
        if waitingFor != nil { followMusic() }
        starting = Task {
            await stopping?.value
            // The listener may be on only for "stop" while an agent is read aloud: the dictation takes it.
            if watchingForStop {
                watchingForStop = false
                listener.onResult = nil
                _ = await listener.stop()
            }
            do {
                try await listener.start(words: words)
                app.appendLog("Listening: microphone \(listener.describeInput())", category: .voice,
                              source: project)
            } catch SpeechListener.Problem.needsDownload {
                listening = false
                asksForDownload = true
            } catch {
                listening = false
                app.appendLog("Could not listen: \(error)", category: .voice, source: project, isError: true)
            }
            starting = nil
            arm()
        }
    }

    /// Turns the microphone off and keeps what was heard in the draft; the dictation stays open.
    func pause() {
        Task { await stopListening() }
    }

    /// Stops listening and adds what was heard to the draft. A stop already under way is waited for,
    /// so nothing is added twice. The dictation stays open meanwhile, so no other one starts.
    private func stopListening() async {
        await starting?.value
        if let stopping {
            await stopping.value
            return
        }
        guard listening else { return }
        let task = Task {
            let text = await listener.stop()
            draft = Self.join(draft, counted(text))
            listener.keepsFinal = nil
            waitingFor = nil
            wakeHeard = false
            listening = false
            stopping = nil
        }
        stopping = task
        await task.value
    }

    /// Closes the dictation without sending anything.
    func cancelRecording() {
        guard let target = recording else { return }
        resuming?.cancel()
        holdUntilSpeech = false
        disarm()
        Task {
            await stopListening()
            guard recording == target else { return }
            recording = nil
            draft = ""
        }
    }

    /// Closes the dictation and delivers the text: pasted into the tab and submitted (the dictation
    /// record first, so the prompt hook knows it was spoken), or as the question's answer.
    func send() {
        guard let target = recording else { return }
        resuming?.cancel()
        holdUntilSpeech = false
        disarm()
        Task {
            await stopListening()
            guard recording == target else { return }
            recording = nil
            // Noise ("." or "Hmm.") is not sent; hands-free listens again all the same.
            let text = DictationText.prompt(draft)
            draft = ""
            switch target {
            case .tab(let project, let tab):
                guard let text else { break }
                await run(VoiceKit.dictatedArguments(sandbox: project, tab: tab), stdin: Data(text.utf8),
                          what: "note the dictation in \(project)", project: project, tab: tab)
                guard let session = app?.terminals[project]?.sessions[tab] else { return }
                await session.write(BracketedPaste.encode(text, submit: true))
                record(.init(speaker: .operator, text: text, tab: tab), in: project)
            case .ask(let ask):
                guard let text, let answer = VoiceAnswer.to(choices: ask.choices, answer: text) else { break }
                self.answer(ask, with: answer)
            }
            // Hands-free stays on: listen for the next thing to say into the same tab.
            switch target {
            case .tab: listenHandsFree(target)
            case .ask(let ask): if let tab = ask.tab { listenHandsFree(.tab(project: ask.project, tab: tab)) }
            }
        }
    }

    private static func join(_ first: String, _ second: String) -> String {
        let second = second.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !first.isEmpty else { return second }
        return second.isEmpty ? first : first + " " + second
    }

    func downloadSpeechModel() {
        Task {
            do {
                try await SpeechListener.download()
            } catch {
                app?.appendLog("Could not download the speech model: \(error)", category: .voice, isError: true)
            }
        }
    }

    func stopSpeaking() {
        Task { await queue.interruptAll() }
    }

    /// Option-Space in Paddock works like the agent tab's microphone (no global hotkey, so no
    /// Accessibility access). Only taken while an agent tab with the voice kit is in front.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard event.keyCode == 49, event.type == .keyDown, event.modifierFlags.contains(.option) else { return event }
            let isRepeat = event.isARepeat
            let taken = MainActor.assumeIsolated { self?.pushToTalkKey(isRepeat: isRepeat) ?? false }
            return taken ? nil : event
        }
    }

    /// Whether the key event was dictation's (and is kept from the terminal).
    private func pushToTalkKey(isRepeat: Bool) -> Bool {
        guard let focused else { return false }
        guard !isRepeat else { return true }
        showPanel(focused.tab)
        // The open dictation, else the tab's question, else the tab's prompt: what its popup's Listen does.
        if let recording {
            toggleListening(recording)
        } else if let ask = asks.first(where: { $0.project == focused.project && $0.tab == focused.tab }) {
            toggleListening(.ask(ask))
        } else {
            toggleListening(.tab(project: focused.project, tab: focused.tab))
        }
        return true
    }
}

// MARK: - Views

/// All of voice for a terminal, in one popup over it: the microphone, and above it the panel: the
/// conversation (what the agent said and asked, what the operator sent), the open question's
/// choices, what is heard (clicking into it pauses the microphone to edit) or a field to type an
/// answer, the Listen, Voice reply, and Hands-free pills, and Dismiss and Send. Anything the agent
/// says or asks opens it; only its close button closes it.
struct VoiceControls: View {
    @Environment(AppModel.self) private var model
    let project: Project
    /// The terminal tab this popup sits over: the popup stays open per tab.
    let terminal: UUID
    /// The agent tab in front, for dictation; nil when a shell is in front and only a question shows.
    let tab: UUID?
    /// The agent's question shown here, if any.
    let ask: VoiceModel.Ask?
    /// The conversation shown here.
    let entries: [VoiceConversation.Entry]
    @FocusState private var editing: Bool
    @State private var typed = ""

    /// What the microphone records for: the question while there is one, else the tab's prompt.
    private var targets: [VoiceModel.Target] {
        [ask.map { .ask($0) }, tab.map { .tab(project: project.name, tab: $0) }].compactMap { $0 }
    }

    var body: some View {
        let voice = model.voice
        let open = voice.recording.map { targets.contains($0) } ?? false
        // The open dictation, if it is one of this popup's; otherwise the one a click would start.
        let target = open ? voice.recording : targets.first
        let listening = open && voice.listening
        VStack(alignment: .trailing, spacing: 6) {
            if let target, open || ask != nil || voice.isPanelShown(terminal) {
                panel(target: target, open: open, listening: listening)
                    .font(.callout)
                    .padding(10)
                    .frame(width: 500)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
            if let target {
                MicrophoneButton(listening: listening) {
                    // Listening again leaves the text, so typing reaches it only after the next pause.
                    editing = false
                    voice.showPanel(terminal)
                    voice.toggleListening(target)
                }
                .help(listening ? "Pause listening (or Option-Space)"
                      : ask != nil ? "Answer aloud" : "Talk to the agent (or Option-Space); right-click for voice settings")
                .contextMenu {
                    settings
                    Divider()
                    voicePicker
                }
            }
        }
        .padding(8)
        // A question opens the popup, and it stays open after the answer.
        .onChange(of: ask?.id, initial: true) { _, id in
            typed = ""
            if id != nil { voice.showPanel(terminal) }
        }
        // So does anything else the agent says.
        .onChange(of: entries.last?.id) { _, _ in
            if entries.last?.speaker == .agent { voice.showPanel(terminal) }
        }
        .alert("Download the speech model?", isPresented: Bindable(voice).asksForDownload) {
            Button("Download") { voice.downloadSpeechModel() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("macOS downloads its on-device speech recognition model for your language once. "
                 + "Speech never leaves this Mac.")
        }
    }

    @ViewBuilder
    private func panel(target: VoiceModel.Target, open: Bool, listening: Bool) -> some View {
        let voice = model.voice
        VStack(alignment: .leading, spacing: 8) {
            if !entries.isEmpty {
                VoiceConversationView(entries: entries)
            }
            if let hearing = voice.heardWhileSpeaking {
                Label(hearing.isEmpty ? "Listening for \"stop\" while it speaks" : "Hearing: " + hearing,
                      systemImage: "ear")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let ask {
                // A question from a tab not shown here is not in this conversation.
                if entries.last(where: \.isQuestion)?.text != SpokenText.dropInvisible(ask.question) {
                    Label {
                        Text(SpokenText.dropInvisible(ask.question)).lineLimit(4)
                    } icon: {
                        Image(systemName: "questionmark.bubble.fill").foregroundStyle(.purple)
                    }
                }
                if !ask.choices.isEmpty {
                    HStack(spacing: 6) {
                        // No keyboard shortcut: Return belongs to the terminal.
                        ForEach(ask.choices, id: \.self) { choice in
                            Button(SpokenText.dropInvisible(choice)) { voice.answer(ask, with: .choice(choice)) }
                        }
                    }
                    .controlSize(.small)
                }
            }
            if open {
                TextField(placeholder(listening: listening), text: Bindable(voice).editableText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...8)
                    .focused($editing)
                    .onChange(of: editing) { _, now in
                        if now { voice.startEditing() }
                    }
                    // Return in the field sends, like Send (Option-Return is a new line); the focus
                    // goes back, so hands-free listens again as after Send.
                    .onSubmit {
                        editing = false
                        voice.send()
                    }
                    .modifier(VoiceTextBox())
            } else if ask != nil {
                TextField("Type an answer, or listen", text: $typed)
                    .textFieldStyle(.plain)
                    .onSubmit(sendTyped)
                    .modifier(VoiceTextBox())
            }
            if voice.voiceReply, voice.suggestsBetterVoice, !voice.voiceHintDismissed {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                    Text("Only basic voices are installed for your language; premium ones sound far better.")
                        .foregroundStyle(.secondary)
                    Button("Get Voices") { voice.openVoiceSettings() }
                        .help("System Settings, Accessibility, Spoken Content, System voice, Manage Voices")
                    Button { voice.voiceHintDismissed = true } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                        .help("Do not show this again")
                }
                .font(.caption)
                .controlSize(.small)
            }
            HStack(spacing: 6) {
                Toggle(isOn: Binding(get: { listening }, set: { _ in
                    editing = false
                    voice.toggleListening(target)
                })) {
                    Label("Listen", systemImage: listening ? "mic.fill" : "mic")
                }
                .toggleStyle(PillToggleStyle(tint: .red))
                .help(listening ? "Pause listening (or Option-Space); say \"send\" on its own to send" : "Listen (or Option-Space)")
                Toggle(isOn: Bindable(voice).voiceReply) {
                    Label("Voice reply", systemImage: "speaker.wave.2.fill")
                }
                .toggleStyle(PillToggleStyle())
                .help(VoiceControls.voiceReplyHelp)
                // The countdown shows in the pill itself while hands-free waits to send.
                Toggle(isOn: Bindable(voice).handsFree) {
                    Label {
                        HandsFreeTitle(sendsAt: voice.sendsAt)
                    } icon: {
                        Image(systemName: "hand.raised.slash.fill")
                    }
                }
                .toggleStyle(PillToggleStyle())
                .help(voice.sendsAt == nil ? VoiceControls.handsFreeHelp : "Sending soon; say \"send\" on its own to send now, \"stop\" to hold it")
                Spacer(minLength: 8)
                if let ask {
                    Button("Dismiss") { voice.answer(ask, with: .dismissed) }
                        .help("Tell the agent you will not answer")
                }
                // While an agent is read aloud, the button stops it.
                if voice.isSpeaking {
                    Button("Cancel") { voice.cancelSpeech() }
                        .buttonStyle(.borderedProminent)
                        .help("Stop reading the agent aloud; the microphone stays off")
                } else {
                    Button("Send") { open ? voice.send() : sendTyped() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!open && ask == nil
                                  || DictationText.prompt(open ? voice.heard : typed) == nil)
                }
            }
            .controlSize(.small)
        }
        // The only way it closes; what was said and not sent is dropped. A question stays (Dismiss
        // answers it) and opens the popup again.
        .overlay(alignment: .topTrailing) {
            Button { voice.closePanel(terminal, targets: targets) } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(open ? "Close without sending" : "Close")
            .offset(x: 4, y: -4)
        }
    }

    @ViewBuilder
    private var settings: some View {
        let voice = model.voice
        Toggle(isOn: Bindable(voice).voiceReply) {
            Label("Voice reply", systemImage: "speaker.wave.2.fill")
        }
        .help(VoiceControls.voiceReplyHelp)
        Toggle(isOn: Bindable(voice).handsFree) {
            Label("Hands-free", systemImage: "hand.raised.slash.fill")
        }
        .help(VoiceControls.handsFreeHelp)
        Menu("Hands-free Turns Off", systemImage: "timer") {
            Picker("After no speech for", selection: Bindable(voice).handsFreeIdleMinutes) {
                ForEach([5, 10, 20, 60, 0], id: \.self) { minutes in
                    Text(minutes == 0 ? "Never" : "\(minutes) minutes").tag(minutes)
                }
            }
            .pickerStyle(.inline)
            Toggle("Keep On in the Background", isOn: Bindable(voice).keepHandsFreeInBackground)
        }
        .help("Hands-free ends after this time without speech, or in the background; it starts off at launch")
        Toggle(isOn: Bindable(voice).waitingMusic) {
            Label("Waiting Music", systemImage: "music.note")
        }
        .help("Quiet music in hands-free while the agent works on what you said")
    }

    /// The voice that reads agents aloud: automatic (the best installed for the Mac's language) or
    /// one the operator picks, and where to get better ones.
    @ViewBuilder
    private var voicePicker: some View {
        let voice = model.voice
        Menu("Voice") {
            Picker("Voice", selection: Bindable(voice).chosenVoice) {
                Text("Automatic" + (voice.automaticVoice.map { " (\($0.name))" } ?? ""))
                    .tag(String?.none)
                ForEach(voice.offeredVoices) { option in
                    Text("\(option.name), \(option.quality.title) (\(option.language))").tag(Optional(option.id))
                }
            }
            .pickerStyle(.inline)
            Divider()
            Button("Get Better Voices...") { voice.openVoiceSettings() }
        }
    }

    /// While hands-free waits for its start word, the field says which.
    private func placeholder(listening: Bool) -> String {
        if model.voice.awaitsWakeWord, let words = model.voice.waitingFor { return "Say \(words.hint) to start" }
        return listening ? "Listening..." : "Nothing heard yet"
    }

    private func sendTyped() {
        guard let ask, let text = DictationText.prompt(typed),
              let answer = VoiceAnswer.to(choices: ask.choices, answer: text) else { return }
        model.voice.answer(ask, with: answer)
    }
}

extension VoiceControls {
    static let voiceReplyHelp = "The agent ends with a spoken summary, or asks you out loud; off, it replies in the terminal as usual"
    static let handsFreeHelp = "Keep listening, starting when you say \"Paddock\" or \"computer\", "
        + "and send on its own 4 seconds after you stop talking; listen for the answer when an agent asks; "
        + "say \"stop\" on its own to keep it from sending"
}

/// The popup's text field as a box: room around the text and a quiet background.
struct VoiceTextBox: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
            .padding(.vertical, 2)
    }
}

/// The back and forth: the agent's lines on the left (questions in purple), the operator's on the
/// right, newest at the bottom, scrolled to it.
struct VoiceConversationView: View {
    let entries: [VoiceConversation.Entry]

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(entries) { entry in
                        bubble(entry).id(entry.id)
                    }
                }
                .padding(.trailing, 4)
            }
            .frame(maxHeight: 220)
            .fixedSize(horizontal: false, vertical: true)
            .onAppear {
                if let last = entries.last?.id { reader.scrollTo(last, anchor: .bottom) }
            }
            .onChange(of: entries.last?.id) { _, last in
                guard let last else { return }
                withAnimation { reader.scrollTo(last, anchor: .bottom) }
            }
        }
    }

    private func bubble(_ entry: VoiceConversation.Entry) -> some View {
        let fromAgent = entry.speaker == .agent
        let tint: Color = fromAgent ? (entry.isQuestion ? .purple : .secondary) : .accentColor
        return HStack {
            if !fromAgent { Spacer(minLength: 40) }
            Text(entry.text)
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                .help(entry.time.formatted(date: .omitted, time: .shortened))
            if fromAgent { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity, alignment: fromAgent ? .leading : .trailing)
    }
}

/// The Hands-free pill's title: "Hands-free", or the seconds left while it waits to send.
struct HandsFreeTitle: View {
    let sendsAt: Date?

    var body: some View {
        if let sendsAt {
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let left = max(0, Int(sendsAt.timeIntervalSince(context.date).rounded(.up)))
                Text("Sending in \(left) s").monospacedDigit()
            }
        } else {
            Text("Hands-free")
        }
    }
}

/// The microphone: a click turns listening on or off.
struct MicrophoneButton: View {
    let listening: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Image(systemName: listening ? "mic.fill" : "mic")
                .font(.title3)
                .foregroundStyle(listening ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                .padding(8)
                .background(.regularMaterial, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(listening ? "Pause listening" : "Talk to the agent")
    }
}

/// A toggle drawn as a pill: filled with its tint when on, quiet when off.
struct PillToggleStyle: ToggleStyle {
    var tint: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            configuration.label
                .labelStyle(.titleAndIcon)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .foregroundStyle(configuration.isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .background(configuration.isOn ? AnyShapeStyle(tint) : AnyShapeStyle(.quaternary), in: Capsule())
                .contentShape(Capsule())
                .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

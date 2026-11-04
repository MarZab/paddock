import Foundation

/// Whether the operator is talking, from the microphone's level (backlog doc Voice, Hands-free).
/// Transcription lags behind speech, so hands-free counts its silence from the sound, not from
/// the text. Speech is a level clearly above the room's background, which it learns as it goes:
/// at once when the room gets quieter, slowly when it gets louder, so talking never becomes the
/// background.
public struct VoiceActivity: Sendable, Equatable {
    /// The background, in dBFS.
    public private(set) var floor: Float
    /// How far above the background speech is.
    public static let margin: Float = 12
    /// Below this nothing is speech, however quiet the room.
    public static let quietest: Float = -55
    /// How much of the gap the background rises per buffer when the level is above it.
    static let rise: Float = 0.002

    public init(floor: Float = -50) {
        self.floor = floor
    }

    /// One buffer's level; true when it is speech.
    public mutating func isSpeech(level: Float) -> Bool {
        let speech = level > max(floor + Self.margin, Self.quietest)
        floor = level < floor ? level : floor + (level - floor) * Self.rise
        floor = min(max(floor, -90), -20)
        return speech
    }

    /// The level of samples in dBFS (RMS), -100 for silence.
    public static func level(of samples: UnsafeBufferPointer<Float>) -> Float {
        guard !samples.isEmpty else { return -100 }
        var sum: Float = 0
        for sample in samples { sum += sample * sample }
        let rms = (sum / Float(samples.count)).squareRoot()
        return rms > 0 ? max(20 * log10(rms), -100) : -100
    }
}

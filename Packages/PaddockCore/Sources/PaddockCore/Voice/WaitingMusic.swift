import Foundation
import Synchronization

/// Quiet music while hands-free waits for an agent (backlog doc Voice, Waiting music): a slowly
/// changing chord, generated here, so there is no recording to license or ship. It fades in over
/// `fadeIn`, and after `thinsAfter` the chords fade out and only a soft note every `bellEvery`
/// is left, so a long wait never turns into a loop the operator notices.
public enum WaitingMusic {
    public static let fadeIn: Double = 3
    public static let thinsAfter: Double = 60
    static let thinning: Double = 20
    static let chordLength: Double = 10
    static let crossfade: Double = 2
    static let bellEvery: Double = 8
    static let bellRing: Double = 6
    /// The loudest a sample gets: well under speech.
    public static let ceiling: Float = 0.3

    /// Cmaj7, Am7, Fmaj7, G, around middle C.
    static let chords: [[Double]] = [
        [261.63, 329.63, 392.00, 493.88],
        [220.00, 261.63, 329.63, 392.00],
        [174.61, 220.00, 261.63, 329.63],
        [196.00, 246.94, 293.66, 392.00]
    ]

    /// The music `time` seconds after it started.
    public static func sample(at time: Double) -> Float {
        guard time > 0 else { return 0 }
        let value = padLevel(at: time) * pad(at: time) + bell(at: time)
        return Float(max(-Double(ceiling), min(Double(ceiling), value)))
    }

    static func padLevel(at time: Double) -> Double {
        let fade = min(1, time / fadeIn)
        let thin = time < thinsAfter ? 1 : max(0, 1 - (time - thinsAfter) / thinning)
        return fade * thin
    }

    /// The chord of the moment, an octave down, each note with a slow swell of its own; the next
    /// chord fades in over the last `crossfade` seconds.
    static func pad(at time: Double) -> Double {
        let position = time / chordLength
        let index = Int(position) % chords.count
        let into = (position - position.rounded(.down)) * chordLength
        let next = smoothstep((into - (chordLength - crossfade)) / crossfade)
        return (1 - next) * chord(index, at: time) + next * chord((index + 1) % chords.count, at: time)
    }

    private static func chord(_ index: Int, at time: Double) -> Double {
        chords[index].enumerated().reduce(0) { sum, note in
            let frequency = note.element / 2
            let swell = 1 + 0.3 * sin(2 * .pi * (0.13 + 0.05 * Double(note.offset)) * time)
            let tone = sin(2 * .pi * frequency * time) + 0.25 * sin(4 * .pi * frequency * time)
            return sum + 0.035 * swell * tone
        }
    }

    /// Once the chords thin out: a soft note every `bellEvery` seconds, from the chord of the
    /// moment, dying away.
    static func bell(at time: Double) -> Double {
        guard time >= thinsAfter else { return 0 }
        let count = Int((time - thinsAfter) / bellEvery)
        let start = thinsAfter + Double(count) * bellEvery
        let age = time - start
        guard age < bellRing else { return 0 }
        let chord = chords[Int(start / chordLength) % chords.count]
        let frequency = chord[count % chord.count]
        return 0.05 * exp(-age / 1.5) * sin(2 * .pi * frequency * age)
    }

    private static func smoothstep(_ value: Double) -> Double {
        let clamped = max(0, min(1, value))
        return clamped * clamped * (3 - 2 * clamped)
    }
}

/// Feeds `WaitingMusic` to an audio callback, which runs on the audio thread: the position and a
/// requested fade-out are atomics, so it never waits on a lock.
public final class WaitingMusicRenderer: Sendable {
    public static let fadeOut: Double = 1

    private let sampleRate: Double
    private let frame = Atomic<Int>(0)
    /// The frame the fade-out began at; -1 while playing.
    private let fadingFrom = Atomic<Int>(-1)

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }

    /// Fades out from now; `render` reports when it is silent.
    public func stop() {
        _ = fadingFrom.compareExchange(expected: -1, desired: frame.load(ordering: .relaxed), ordering: .relaxed)
    }

    /// Fills `samples` with the next stretch of music. Returns false once a fade-out is over (the
    /// rest is silence).
    @discardableResult
    public func render(into samples: UnsafeMutableBufferPointer<Float>) -> Bool {
        let first = frame.wrappingAdd(samples.count, ordering: .relaxed).oldValue
        let fading = fadingFrom.load(ordering: .relaxed)
        let fadeFrames = Self.fadeOut * sampleRate
        var playing = true
        for index in samples.indices {
            let position = first + index
            var gain: Float = 1
            if fading >= 0 {
                let done = Double(position - fading) / fadeFrames
                gain = Float(max(0, 1 - done))
                if done >= 1 { playing = false }
            }
            samples[index] = gain == 0 ? 0 : gain * WaitingMusic.sample(at: Double(position) / sampleRate)
        }
        return playing
    }
}

import Foundation
import Testing
@testable import PaddockCore

struct HandsFreeLimitsTests {
    @Test func endsAfterTheIdleTime() {
        let limits = HandsFreeLimits(idleMinutes: 20, keepInBackground: false)
        #expect(limits.reason(idleFor: 19 * 60 + 59, appActive: true) == nil)
        #expect(limits.reason(idleFor: 20 * 60, appActive: true) == .idle(minutes: 20))
        #expect(limits.reason(idleFor: 3 * 3600, appActive: true) == .idle(minutes: 20))
    }

    @Test func zeroMeansNeverAndTheTimeIsCapped() {
        #expect(HandsFreeLimits(idleMinutes: 0, keepInBackground: false).idleMinutes == nil)
        #expect(HandsFreeLimits(idleMinutes: -5, keepInBackground: false).idleMinutes == nil)
        let never = HandsFreeLimits(idleMinutes: 0, keepInBackground: false)
        #expect(never.reason(idleFor: 10 * 3600, appActive: true) == nil)
        let huge = HandsFreeLimits(idleMinutes: 100_000, keepInBackground: false)
        #expect(huge.idleMinutes == HandsFreeLimits.maxIdleMinutes)
    }

    @Test func endsWhenPaddockGoesToTheBackgroundUnlessKept() {
        let ends = HandsFreeLimits(idleMinutes: 20, keepInBackground: false)
        #expect(ends.reason(idleFor: 0, appActive: false) == .background)
        #expect(ends.reason(idleFor: 0, appActive: true) == nil)
        let keeps = HandsFreeLimits(idleMinutes: 20, keepInBackground: true)
        #expect(keeps.reason(idleFor: 0, appActive: false) == nil)
        // kept in the background, it still ends when idle
        #expect(keeps.reason(idleFor: 21 * 60, appActive: false) == .idle(minutes: 20))
    }

    @Test func theMessagesSayWhy() {
        #expect(HandsFreeLimits.Reason.idle(minutes: 20).message.contains("20 min"))
        #expect(HandsFreeLimits.Reason.background.message.contains("background"))
    }

    /// Only the operator turns hands-free on: nothing the sandbox can send is a message about it.
    @Test func noMessageFromTheSandboxTurnsHandsFreeOn() {
        let kinds = ["hands-free", "handsfree", "hands_free", "listen", "mic", "microphone", "voice", "status"]
        for kind in kinds {
            let line = #"{"id":"v-1a2b3c4d","kind":"\#(kind)","text":"on","tab":"","time":1}"#
            #expect(VoiceMessage(line: line) == nil)
        }
    }
}

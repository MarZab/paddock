import Foundation
import Testing
@testable import PaddockCore

/// PAD-33: one static mark per project, the most urgent first.
@Suite("ProjectBadge")
struct ProjectBadgeTests {
    /// PAD-63: the mark is the sandbox's; the agents have rows of their own.
    @Test func theMarkIsTheSandboxsAndItsRequests() {
        #expect(ProjectBadge(state: .running) == .running)
        #expect(ProjectBadge(state: .running, requests: 1) == .needsYou)
        #expect(ProjectBadge(state: .stopped) == .stopped)
        #expect(ProjectBadge(state: nil) == .none)
    }

    @Test func otherStatesAreChangesUnlessTheySoundWrong() {
        #expect(ProjectBadge(state: .other("starting")) == .changing("starting"))
        #expect(ProjectBadge(state: .other("stopping")) == .changing("stopping"))
        #expect(ProjectBadge(state: .other("Error")) == .problem("Error"))
        #expect(ProjectBadge(state: .other("start_failed")) == .problem("start_failed"))
    }

    @Test func helpSaysItInWords() {
        #expect(ProjectBadge.help(state: .running, requests: 2) == "running, 2 approval requests waiting for you")
        #expect(ProjectBadge.help(state: .running, requests: 1) == "running, 1 approval request waiting for you")
        #expect(ProjectBadge.help(state: nil) == "no sandbox yet")
    }

    @Test func tabMarksKnowWhenSomethingIsUnseen() {
        var marks = AgentTabMarks()
        let tab = UUID()
        _ = marks.update(tab: tab, activity: .working, isShown: false)
        #expect(!marks.hasUnseen)
        _ = marks.update(tab: tab, activity: .none, isShown: false)
        #expect(marks.hasUnseen)
        marks.seen(tab)
        #expect(!marks.hasUnseen)
    }
}

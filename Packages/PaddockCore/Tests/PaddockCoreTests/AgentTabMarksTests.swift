import Foundation
import Testing
@testable import PaddockCore

struct AgentTabMarksTests {
    @Test func aFinishedTabStaysMarkedUntilSeen() {
        var marks = AgentTabMarks()
        let tab = UUID()
        #expect(marks.update(tab: tab, activity: .working, isShown: false) == .working)
        #expect(marks.update(tab: tab, activity: .waiting, isShown: false) == .waiting)
        #expect(marks.update(tab: tab, activity: .none, isShown: false) == .finished)
        // later updates without a change keep the mark
        #expect(marks.update(tab: tab, activity: .none, isShown: false) == .finished)
        marks.seen(tab)
        #expect(marks.update(tab: tab, activity: .none, isShown: false) == .none)
    }

    @Test func aTabTheOperatorIsLookingAtIsNeverMarked() {
        var marks = AgentTabMarks()
        let tab = UUID()
        _ = marks.update(tab: tab, activity: .working, isShown: true)
        #expect(marks.update(tab: tab, activity: .none, isShown: true) == .none)
    }

    @Test func newWorkClearsTheMarkAndAnIdleTabNeverGetsOne() {
        var marks = AgentTabMarks()
        let tab = UUID()
        #expect(marks.update(tab: tab, activity: .none, isShown: false) == .none)
        _ = marks.update(tab: tab, activity: .working, isShown: false)
        #expect(marks.update(tab: tab, activity: .none, isShown: false) == .finished)
        #expect(marks.update(tab: tab, activity: .working, isShown: false) == .working)
    }

    @Test func aForgottenTabStartsOver() {
        var marks = AgentTabMarks()
        let tab = UUID()
        _ = marks.update(tab: tab, activity: .working, isShown: false)
        _ = marks.update(tab: tab, activity: .none, isShown: false)
        marks.forget(tab)
        #expect(marks.update(tab: tab, activity: .none, isShown: false) == .none)
    }
}

import Foundation
@testable import PaddockCore
import Testing

@Suite("ProjectGroups")
struct ProjectGroupsTests {
    func project(_ name: String, group: String? = nil) -> Project {
        Project(name: name, folder: "/p/\(name)", group: group)
    }

    @Test func withoutGroupsOneSectionKeepsTheOrder() {
        let projects = [project("a"), project("b")]
        #expect(ProjectGroups.sections(projects) == [.init(group: nil, projects: projects)])
        #expect(ProjectGroups.sections([]) == [.init(group: nil, projects: [])])
    }

    @Test func groupsByNameThenOtherLast() {
        let a = project("a"), b = project("b", group: "Work"), c = project("c", group: "art"), d = project("d", group: "work")
        let sections = ProjectGroups.sections([a, b, c, d])
        #expect(sections.map(\.group) == ["art", "Work", nil])
        #expect(sections.map { $0.projects.map(\.name) } == [["c"], ["b", "d"], ["a"]])
        #expect(ProjectGroups.names([a, b, c, d]) == ["art", "Work"])
    }

    @Test func noOtherWhenEveryProjectHasAGroup() {
        #expect(ProjectGroups.sections([project("a", group: "x")]).map(\.group) == ["x"])
    }

    @Test func blankGroupsAreNone() {
        #expect(ProjectGroups.normalized("  ") == nil)
        #expect(ProjectGroups.normalized(" Work \n") == "Work")
        #expect(project("a", group: " ").group == nil)
    }

    @Test func foldCyclesOpenRunningClosed() {
        #expect(ProjectGroups.Fold.open.next == .running)
        #expect(ProjectGroups.Fold.running.next == .closed)
        #expect(ProjectGroups.Fold.closed.next == .open)
        let projects = [project("a"), project("b")]
        let running: (Project) -> Bool = { $0.name == "b" }
        #expect(ProjectGroups.Fold.open.shown(projects, isRunning: running).map(\.name) == ["a", "b"])
        #expect(ProjectGroups.Fold.running.shown(projects, isRunning: running).map(\.name) == ["b"])
        #expect(ProjectGroups.Fold.closed.shown(projects, isRunning: running).isEmpty)
    }

    @Test func theFileKeepsTheGroupAndOlderFilesHaveNone() throws {
        let saved = project("a", group: "Work")
        let decoded = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(saved))
        #expect(decoded.group == "Work")
        let old = #"{"id":"\#(UUID().uuidString)","name":"a","folder":"/p/a","agent":"claude","provider":"agent-default"}"#
        #expect(try JSONDecoder().decode(Project.self, from: Data(old.utf8)).group == nil)
    }
}

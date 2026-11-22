import Foundation

/// The sidebar's project sections (PAD-145; backlog doc UI, Project groups): one per group the
/// operator gave a project, by name, then Other for the projects without one. With no groups at
/// all there is one section without a group, the plain Projects list.
public enum ProjectGroups {
    /// The section of the projects without a group, once any project has one.
    public static let otherTitle = "Other"

    public struct Section: Sendable, Equatable, Identifiable {
        /// The group's name; nil for Other, and for the one section when no project has a group.
        public let group: String?
        public let projects: [Project]

        public var id: String { group.map { "group:" + $0 } ?? "other" }
    }

    /// How a group shows: every project, only the running ones, or none (its title with the number
    /// of running projects). Clicking the title goes to the next one.
    public enum Fold: String, Sendable, Equatable, CaseIterable {
        case open, running, closed

        public var next: Fold {
            switch self {
            case .open: .running
            case .running: .closed
            case .closed: .open
            }
        }

        /// The projects of a section that show in this fold.
        public func shown(_ projects: [Project], isRunning: (Project) -> Bool) -> [Project] {
            switch self {
            case .open: projects
            case .running: projects.filter(isRunning)
            case .closed: []
            }
        }
    }

    /// A group name as kept: trimmed, nil when empty.
    public static func normalized(_ group: String?) -> String? {
        guard let trimmed = group?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// The projects in sections, each keeping the order it was given. Groups sort by name, ignoring
    /// case; names that differ only in case are one group, titled as its first project has it.
    public static func sections(_ projects: [Project]) -> [Section] {
        var titles: [String: String] = [:]
        var members: [String: [Project]] = [:]
        var other: [Project] = []
        for project in projects {
            guard let group = normalized(project.group) else {
                other.append(project)
                continue
            }
            let key = group.lowercased()
            if titles[key] == nil {
                titles[key] = group
            }
            members[key, default: []].append(project)
        }
        guard !members.isEmpty else { return [Section(group: nil, projects: projects)] }
        let grouped = members.keys.sorted()
            .map { Section(group: titles[$0], projects: members[$0] ?? []) }
        return other.isEmpty ? grouped : grouped + [Section(group: nil, projects: other)]
    }

    /// Every group name in use, sorted, for the field that sets one.
    public static func names(_ projects: [Project]) -> [String] {
        sections(projects).compactMap(\.group)
    }
}

import Foundation

/// What Paddock asks before it quits while agents run (PAD-153.4; backlog doc UI, Agents left
/// running): quitting ends only `sbx` on the Mac, so the agents go on in their sandboxes with no
/// terminal, and show as left running at the next launch.
public enum QuitWarning {
    /// A project's agents that run now: in its agent tabs, and in shell tabs an agent reports from.
    public struct Running: Sendable, Equatable {
        public let project: String
        public let agents: Int
        /// Of those, the ones working or waiting for the operator now.
        public let busy: Int

        public init(project: String, agents: Int, busy: Int) {
            self.project = project
            self.agents = agents
            self.busy = busy
        }
    }

    /// The alert's title and message, or nil when no agent runs (Paddock quits without asking).
    public static func text(_ running: [Running]) -> (title: String, message: String)? {
        let shown = running.filter { $0.agents > 0 }.sorted { $0.project < $1.project }
        let total = shown.reduce(0) { $0 + $1.agents }
        guard total > 0 else { return nil }
        let title = total == 1 ? "Quit Paddock while an agent runs?" : "Quit Paddock while \(total) agents run?"
        let places = shown.map { project in
            let busy = project.busy > 0 ? " (\(project.busy) working)" : ""
            return project.agents == 1 ? "\(project.project)\(busy)" : "\(project.project): \(project.agents)\(busy)"
        }
        let message = "In \(places.joined(separator: ", ")). "
            + "\(total == 1 ? "It keeps" : "They keep") running in \(total == 1 ? "its sandbox" : "their sandboxes") with no terminal; "
            + "when Paddock opens again, \(total == 1 ? "it shows" : "they show") as left running, to take over or stop."
        return (title, message)
    }
}

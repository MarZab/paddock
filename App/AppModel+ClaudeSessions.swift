import AppKit
import PaddockCore

/// Claude's sessions kept on this Mac (PAD-127, backlog doc UI, Claude sessions).
extension AppModel {
    /// What the project's sessions folder holds now; nil when it has none yet.
    func claudeSessionsSummary(of project: Project) -> ClaudeSessions.Summary? {
        ClaudeSessions.summary(folder: ClaudeSessions.folder(project: project.name, paths: paths))
    }

    /// Turns keeping on or off; the sandbox follows at its next create (a recreate item).
    func setKeepsClaudeSessions(_ keeps: Bool, for project: Project) {
        guard withSaved(project, { self.setKeepsClaudeSessions(keeps, for: $0) }) else { return }
        guard var updated = projects.project(named: project.name), updated.keepsClaudeSessions != keeps else { return }
        updated.keepsClaudeSessions = keeps
        saveProject(updated, what: "Claude sessions setting")
    }

    func revealClaudeSessions(of project: Project) {
        let folder = ClaudeSessions.folder(project: project.name, paths: paths)
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder, isDirectory: true)])
    }

    /// Removes every session in the folder (after the operator confirmed); links are removed as
    /// links, never followed.
    func clearClaudeSessions(of project: Project) {
        let folder = ClaudeSessions.folder(project: project.name, paths: paths)
        do {
            try ClaudeSessions.clear(folder: folder)
            appendLog("Cleared Claude's sessions of \(project.name)", source: project.name)
        } catch {
            fail("Could not clear Claude's sessions of \(project.name): \(error.localizedDescription)", in: project.name)
        }
    }
}

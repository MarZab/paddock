import PaddockA2UI
import PaddockCore
import SwiftUI

/// An interactive tab (`paddock ui`; backlog doc Browser, interactive tabs): the agent's A2UI
/// surfaces, drawn natively by A2UI's own renderer (PaddockA2UI). The app model keeps the tab
/// while it is hidden, reads what the agent sends at each new revision, and draws it again from
/// the first message on the tab menu's Refresh.
struct A2UIShowView: View {
    @Environment(AppModel.self) private var model
    let project: Project
    let show: BrowserSessions.Show

    var body: some View {
        let command = model.terminals[project.name]?.viewCommands[ProjectTerminals.showTab(show.id)]
        let redraw = command?.kind == .reload ? command?.serial ?? 0 : 0
        Group {
            if let tab = model.terminals[project.name]?.a2uiTabs[show.id] {
                A2UITabView(tab: tab)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: "\(show.revision)-\(redraw)") {
            await model.syncA2UI(show: show, redraw: redraw, of: project)
        }
    }
}

/// An A2UI tab's way to its sandbox: every command through `ProjectRunner` (and so `A2UICommands`).
struct AppA2UILink: A2UITabLink {
    let project: Project
    let show: String
    let runner: @Sendable () async throws -> ProjectRunner

    func deliver(_ line: Data) async throws {
        try await runner().a2uiDeliver(line, show: show, of: project)
    }

    func media(_ source: A2UIMedia.Source, kind: A2UIMedia.Kind) async throws -> (mimeType: String, data: Data) {
        try await runner().a2uiMedia(source, kind: kind, show: show, of: project)
    }

    func openInSandbox(_ url: URL) async throws {
        try await runner().a2uiOpen(url, of: project)
    }
}

extension AppModel {
    /// An interactive tab (backlog doc Browser, interactive tabs): reads what the agent sent since
    /// the last read into its A2UI tab, after drawing it again from the first message when the
    /// operator asked (Refresh, `redraw` above the last one). One read per tab at a time; a change
    /// meanwhile reads again after.
    func syncA2UI(show: BrowserSessions.Show, redraw: Int, of project: Project) async {
        guard let terminals = terminals[project.name] else { return }
        let id = show.id
        if redraw > (terminals.a2uiRedrawn[id] ?? 0) {
            terminals.a2uiRedrawn[id] = redraw
            terminals.resetA2UI(id)
            // The agent hears that the operator drew it again.
            Task { try? await runner().navigateShow(.reload, show: id, of: project) }
        }
        guard !terminals.a2uiReading.contains(id) else {
            terminals.a2uiAgain.insert(id)
            return
        }
        terminals.a2uiReading.insert(id)
        defer { terminals.a2uiReading.remove(id) }
        repeat {
            terminals.a2uiAgain.remove(id)
            let tab = terminals.a2uiTab(id) { makeA2UITab(show: id, of: project) }
            do {
                let chunk = try await runner().a2uiMessages(show: id, from: tab.offset, of: project)
                // Drawn again meanwhile: read the new tab from its start.
                guard terminals.a2uiTabs[id] === tab else {
                    terminals.a2uiAgain.insert(id)
                    continue
                }
                let refused = tab.take(chunk)
                if let first = refused.first {
                    fail("\(show.title): Paddock did not draw \(refused.count) of the agent's messages (line \(first.line ?? 0): \(first.reason)); the agent was told",
                         in: project.name)
                }
            } catch {
                fail("Could not read \(show.title) from the sandbox: \(String(describing: error))", in: project.name)
            }
        } while terminals.a2uiAgain.contains(id)
    }

    private func makeA2UITab(show id: String, of project: Project) -> A2UITab {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Paddock A2UI", isDirectory: true)
            .appendingPathComponent(project.name + "-" + id, isDirectory: true)
        let link = AppA2UILink(project: project, show: id) { [weak self] in
            guard let self else { throw AppError("Paddock is closing") }
            return try await self.runner()
        }
        return A2UITab(id: id, link: link, folder: folder)
    }
}

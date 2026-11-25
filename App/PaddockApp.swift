import AppKit
import PaddockCore
import SwiftUI

@main
struct PaddockApp: App {
    @State private var model = AppModel()
    /// Asks before quitting while agents run (PAD-153.4).
    @NSApplicationDelegateAdaptor private var delegate: PaddockAppDelegate

    init() {
        // Tooltips (`.help`) show after 0.2 s instead of about a second: the icon-only actions in
        // the lists are explained by them. A default, so `defaults write` can still change it.
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 200])
    }

    var body: some Scene {
        WindowGroup("Paddock") {
            ContentView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 560)
                .task {
                    delegate.model = model
                    model.start()
                }
        }
        // macOS 26 rounds a window's corners by its toolbar; the compact one gets the smaller radius.
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            // One window: a second one showed the same projects and tabs again (PAD-144). Not a
            // `Window` scene, which quits the app (and its sessions) when the window closes.
            CommandGroup(replacing: .newItem) {}
            // Paddock itself, as the sidebar's System section is (backlog doc UI, System menu).
            CommandMenu("System") {
                // Pages in the main window, not windows of their own.
                Button("Log") { model.showLog() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Processes") { model.showSbxProcesses() }
                Divider()
                Toggle("Verbose Log", isOn: $model.verboseLog)
                Button("Log Files") { model.revealLogFiles() }
                Button("Crash Reports") { model.revealCrashReports() }
                Button("Capture Diagnostics") { model.captureDiagnostics() }
                Divider()
                Button("Edit Paddock's Config") { model.editAppConfig() }
            }
        }
    }
}

/// Quitting ends only sbx on the Mac: the agents go on in their sandboxes with no terminal. While
/// any runs, Paddock asks first (`QuitWarning`); Cancel keeps it open.
@MainActor
final class PaddockAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, let text = QuitWarning.text(model.runningAgents()) else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = text.title
        alert.informativeText = text.message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit Anyway")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }
}

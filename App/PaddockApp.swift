import SwiftUI

@main
struct PaddockApp: App {
    @State private var model = AppModel()

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
                .task { model.start() }
        }
        // macOS 26 rounds a window's corners by its toolbar; the compact one gets the smaller radius.
        .windowToolbarStyle(.unifiedCompact)
        .commands {
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

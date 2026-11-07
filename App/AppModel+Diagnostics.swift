import AppKit
import PaddockCore

/// The System menu's diagnostics (backlog doc UI, System menu).
extension AppModel {
    /// System > Capture Diagnostics: what the watchdog captures in a hang, now, then shown in Finder.
    func captureDiagnostics() {
        let folder = HangWatchdog.folder()
        appendLog("Capturing diagnostics into \(folder.path)")
        Task {
            await HangWatchdog.run(into: folder, reason: "the operator asked (System > Capture Diagnostics)")
            appendLog("Diagnostics captured in \(folder.path)")
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        }
    }

    /// Shows this session's log file in Finder, next to the earlier sessions' (System > Log Files).
    func revealLogFiles() {
        NSWorkspace.shared.activateFileViewerSelecting([LogFile.shared.url])
    }
}

import PaddockCore

/// Recreating a sandbox when the operator asks (PAD-132, backlog doc UI, Project Info).
extension AppModel {
    /// The title bar's Recreate: what Sync's recreate items do, at any time.
    func recreateSandbox(_ project: Project) {
        apply(SyncItem(id: "recreate", kind: .sandbox, summary: "recreate the sandbox", apply: .recreate), for: project)
    }
}

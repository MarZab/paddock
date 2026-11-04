import AppKit
import PaddockCore
import UserNotifications

/// macOS notifications for approval requests that arrive while Paddock is in the background: the
/// agent is waiting on them. Allow, Block and Dismiss answer from the notification; clicking it opens the
/// project. In the foreground the project's own banner shows them instead.
@MainActor
final class ApprovalNotifier: NSObject, UNUserNotificationCenterDelegate {
    private nonisolated static let category = "paddock.approval"
    private nonisolated static let approvalKey = "approval"
    private nonisolated static let sandboxKey = "sandbox"

    /// The operator answered from a notification: the approval's id and sbx's option id, or `block`
    /// (Paddock's own: a sandbox deny, then Dismiss).
    var onAnswer: (@MainActor (_ approval: String, _ option: String) -> Void)?
    /// The operator clicked a notification: the sandbox whose request it was.
    var onOpen: (@MainActor (_ sandbox: String) -> Void)?

    /// Requests already known, notified or not; nothing that was pending at launch is notified.
    private var known: Set<String> = []
    private var seeded = false
    private var started = false
    private var askedPermission = false

    func start() {
        guard !started else { return }
        started = true
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // Allow and Block change the sandbox's rules: not from a locked screen.
        let allow = UNNotificationAction(identifier: "allow", title: "Allow", options: [.authenticationRequired])
        let block = UNNotificationAction(identifier: "block", title: "Block", options: [.authenticationRequired, .destructive])
        let dismiss = UNNotificationAction(identifier: "dismiss", title: "Dismiss")
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.category, actions: [allow, block, dismiss],
                                                                 intentIdentifiers: [])])
    }

    /// The requests the projects show now. New ones are notified while the app is in the background;
    /// notifications for answered ones are taken back.
    func update(_ shown: [SbxApproval]) {
        guard started else { return }
        let ids = Set(shown.map(\.id))
        let gone = known.subtracting(ids)
        if !gone.isEmpty {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: Array(gone))
        }
        // The first list is what was pending before Paddock looked: not news.
        let arrived = seeded ? shown.filter { !known.contains($0.id) } : []
        seeded = true
        known = ids
        guard !NSApp.isActive else { return }
        for approval in arrived { post(approval) }
    }

    private func post(_ approval: SbxApproval) {
        let content = UNMutableNotificationContent()
        content.title = "\(approval.sandboxName) wants to reach a host"
        content.body = approval.title
        content.sound = .default
        content.userInfo = [Self.approvalKey: approval.id, Self.sandboxKey: approval.sandboxName]
        // Allow, Block and Dismiss from the notification only when sbx offers exactly those.
        if Set(approval.options.map(\.id)) == ["allow", "dismiss"] {
            content.categoryIdentifier = Self.category
        }
        let request = UNNotificationRequest(identifier: approval.id, content: content, trigger: nil)
        Task {
            let center = UNUserNotificationCenter.current()
            if !askedPermission {
                askedPermission = true
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
            try? await center.add(request)
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        guard let approval = info[Self.approvalKey] as? String, let sandbox = info[Self.sandboxKey] as? String else { return }
        await MainActor.run {
            switch action {
            case "allow", "block", "dismiss": onAnswer?(approval, action)
            default: onOpen?(sandbox)
            }
        }
    }

    /// In the foreground the project's banner shows the request.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        []
    }
}

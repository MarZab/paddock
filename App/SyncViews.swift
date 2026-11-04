import AppKit
import PaddockCore
import SwiftUI

/// One notice on a project's Info tab: an icon for its kind, what it is, and its buttons on the
/// right, on a tinted background. Every notice there (warnings, differences to apply, suggestions,
/// approval requests) uses it, so they all look alike.
struct NoticeRow<Actions: View>: View {
    enum Kind {
        /// Something is wrong (a folder Paddock would refuse, say).
        case warning
        /// The sandbox differs from the project and needs a change (Apply, Recreate, Review).
        case change
        /// Something Paddock suggests; the operator may ignore it.
        case suggestion
        /// The agent asks for something (sbx's approval requests).
        case request

        var systemImage: String {
            switch self {
            case .warning: "exclamationmark.triangle.fill"
            case .change: "arrow.triangle.2.circlepath"
            case .suggestion: "lightbulb"
            case .request: "hand.raised"
            }
        }

        var tint: Color {
            switch self {
            case .warning, .change: .orange
            case .suggestion, .request: .yellow
            }
        }
    }

    let kind: Kind
    let text: String
    var help: String?
    let actions: Actions

    init(_ kind: Kind, _ text: String, help: String? = nil, @ViewBuilder actions: () -> Actions) {
        self.kind = kind
        self.text = text
        self.help = help
        self.actions = actions()
    }

    var body: some View {
        HStack {
            Label(text, systemImage: kind.systemImage)
                .help(help ?? text)
            Spacer()
            actions
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(kind.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }
}

extension NoticeRow where Actions == EmptyView {
    init(_ kind: Kind, _ text: String, help: String? = nil) {
        self.init(kind, text, help: help) { EmptyView() }
    }
}

/// What waits for the operator, shown only when something does: warnings, an `sbxenv.yaml` to
/// confirm, and the sandbox's differences (folder, agent, the environment, kits, the gateway
/// rule), each a `NoticeRow` with Apply or Recreate (change the sandbox; nothing is saved back)
/// (backlog doc App config, Sync).
struct AttentionSections: View {
    @Environment(AppModel.self) private var model
    let project: Project
    @State private var confirmRecreate: SyncItem?

    init(project: Project) {
        self.project = project
    }

    var body: some View {
        let warnings = ProjectWarnings.warnings(for: project, model: model)
        // An sbxenv.yaml never confirmed, or changed since.
        let approval: Bool = model.needsConfirmation(for: project)
        // Paddock's service denies are a suggestion on the Info tab, not a warning.
        let items = model.syncItems(for: project).filter { $0.apply != .create && $0.id != SyncItem.serviceDeniesID }
        if !warnings.isEmpty || approval || !items.isEmpty {
            // One stack, so the dialog is attached once (a modifier on ForEach goes to every row).
            VStack(alignment: .leading, spacing: 8) {
                notices(warnings: warnings, approval: approval, items: items)
            }
            .confirmationDialog("Recreate \(project.name)?", isPresented: Binding(get: { confirmRecreate != nil }, set: { if !$0 { confirmRecreate = nil } }),
                                presenting: confirmRecreate) { item in
                Button("Recreate Sandbox", role: .destructive) { model.apply(item, for: project) }
            } message: { _ in
                Text("sbx cannot change this in place. The sandbox is removed and created again from the project file; anything in it outside the project folder is lost.")
            }
        }
    }

    @ViewBuilder
    private func notices(warnings: [String], approval: Bool, items: [SyncItem]) -> some View {
        ForEach(warnings, id: \.self) { warning in
            NoticeRow(.warning, warning)
        }
        if approval {
            NoticeRow(.change, "sbxenv.yaml is new or changed; confirm it before the next create") {
                Button("Review...") { model.confirmation = .init(project: project.name, then: .nothing) }
            }
            .disabled(model.isBusy(project))
        }
        ForEach(items) { item in
            NoticeRow(.change, item.summary,
                      help: "The project file is what counts; \(item.applyIsDestructive ? "Recreate" : "Apply") changes the sandbox to match it.") {
                if item.apply != nil {
                    Button(item.applyIsDestructive ? "Recreate" : "Apply") {
                        if item.applyIsDestructive { confirmRecreate = item } else { model.apply(item, for: project) }
                    }
                    .help("Change the sandbox to match the project file")
                }
            }
            .disabled(model.isBusy(project))
        }
    }
}

/// Confirm a project's `sbxenv.yaml` and its own kits: what the agent may reach, next to sbx's
/// global rules, each host allowed or declined; what its kits reach while they install; its extra
/// folders, ports, and environment. Confirming records this version and the declined hosts; the
/// next create applies them (backlog doc Project config file), and what waited for it goes on.
struct ConfigConfirmSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let confirmation: AppModel.ConfigConfirmation
    @State private var declined: Set<String> = []

    init(confirmation: AppModel.ConfigConfirmation) {
        self.confirmation = confirmation
    }

    var body: some View {
        let project = model.project(named: confirmation.project)
        let review = project.flatMap { model.environmentReview(for: $0) }
        VStack(alignment: .leading, spacing: 12) {
            Text("Confirm sbxenv.yaml for \(confirmation.project)").font(.title3.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let review {
                        contents(review)
                    } else {
                        Text("The project has no sbxenv.yaml any more.").foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 200, maxHeight: 480)
            HStack {
                if let review, !review.canApprove {
                    Text("Fix the file first; Paddock refuses it as it is.").foregroundStyle(.red)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle) { model.confirm(confirmation, declined: declined) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!(review?.canApprove ?? false))
            }
        }
        .padding(20)
        .frame(width: 660)
        .onAppear { declined = Set(project?.declinedHosts ?? []) }
    }

    @ViewBuilder
    private func contents(_ review: EnvironmentReview) -> some View {
        let environment = review.environment
        if !environment.problems.isEmpty {
            section("Refused") {
                ForEach(environment.problems.map(\.description), id: \.self) { problem in
                    Label(problem, systemImage: "xmark.octagon").foregroundStyle(.red).textSelection(.enabled)
                }
            }
        }
        section("Kits") {
            if environment.kits.isEmpty {
                Text("None of its own; Paddock's kits are added from the project's settings.").foregroundStyle(.secondary)
            }
            ForEach(environment.kits, id: \.source) { kit in
                HStack(alignment: .firstTextBaseline) {
                    Text(kit.source).font(.body.monospaced()).textSelection(.enabled)
                    Spacer()
                    Text(origin(kit.origin)).foregroundStyle(.secondary)
                }
            }
        }
        section("The agent may reach") {
            if review.runtimeHosts.isEmpty {
                Text("Nothing beyond sbx's global rules.").foregroundStyle(.secondary)
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                ForEach(review.runtimeHosts) { host in
                    GridRow {
                        Toggle(isOn: Binding(get: { !declined.contains(host.host) },
                                             set: { if $0 { declined.remove(host.host) } else { declined.insert(host.host) } })) {
                            EmptyView()
                        }
                        .toggleStyle(.checkbox)
                        .help("Uncheck to decline: the sandbox gets a deny for it")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(host.host).textSelection(.enabled)
                            if !host.methods.isEmpty || !host.paths.isEmpty {
                                Text(([host.methods.joined(separator: ",")] + host.paths).filter { !$0.isEmpty }.joined(separator: " "))
                                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                        Text(hostNote(host)).foregroundStyle(host.allowedGlobally == nil ? Color.secondary : Color.orange)
                    }
                }
            }
            if !review.deniedHosts.isEmpty {
                Text("Its kits deny: " + review.deniedHosts.joined(separator: ", ")).foregroundStyle(.secondary)
            }
        }
        if !review.installHosts.isEmpty {
            section("While its kits install") {
                Text(review.installHosts.joined(separator: ", ")).textSelection(.enabled)
                Text("Open only while sbx builds and installs the kits, before the agent starts.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        if !environment.extraFolders.isEmpty {
            section("Extra folders") {
                ForEach(environment.extraFolders, id: \.path) { folder in
                    Text((folder.path as NSString).abbreviatingWithTildeInPath
                        + (folder.readOnly ? ", read-only" : ", writable")
                        + (folder.otherProject.map { ", the folder of project \($0)" } ?? ""))
                        .foregroundStyle(folder.readOnly ? Color.primary : Color.orange)
                }
            }
        }
        if let file = environment.file, !file.ports.isEmpty || !file.env.isEmpty {
            section("Ports and environment") {
                ForEach(Array(file.ports.enumerated()), id: \.offset) { _, port in
                    Text("Publishes sandbox port \(port.sandbox)" + (port.host.map { " on this Mac's \($0)" } ?? ""))
                }
                if !file.env.isEmpty {
                    Text("Sets " + file.env.keys.sorted().joined(separator: ", ")).textSelection(.enabled)
                }
            }
        }
    }

    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
    }

    private func origin(_ origin: ProjectEnvironment.Kit.Origin) -> String {
        switch origin {
        case .catalog: "sbx's"
        case .local: "the project's own, built at create"
        case .refused: "refused"
        }
    }

    private func hostNote(_ host: EnvironmentReview.Host) -> String {
        let kit = "from \(host.kit)"
        guard let rule = host.allowedGlobally else { return kit }
        return "\(kit); allowed already by global \(rule), declining denies it here"
    }

    private var confirmTitle: String {
        switch confirmation.then {
        case .nothing: "Confirm"
        case .create, .open: "Confirm and Create"
        }
    }
}

/// Warnings about a project's sandbox: a folder Paddock would refuse. Paddock's own ports
/// (llmman, other gateways) that nothing denies show in its Ports section ("not denied").
enum ProjectWarnings {
    @MainActor
    static func warnings(for project: Project, model: AppModel) -> [String] {
        var warnings: [String] = []
        let policy = FolderPolicy(home: NSHomeDirectory(), paddockConfigDirectory: model.paths.configDirectory)
        do {
            try policy.check(project.folder)
        } catch {
            warnings.append("Its folder would not be allowed for a new project: \(error.description)")
        }
        return warnings
    }
}

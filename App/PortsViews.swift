import AppKit
import PaddockCore
import SwiftUI

extension PortRow.Kind {
    var title: String {
        switch self {
        case .published: "Published"
        case .hostService: "Host"
        }
    }
}

extension PortRow.State {
    var title: String {
        switch self {
        case .live: "in effect"
        case .notDenied: "not denied"
        }
    }

    /// The operator has something to decide: a port to deny.
    var differs: Bool {
        switch self {
        case .notDenied: true
        case .live: false
        }
    }

    var color: Color {
        switch self {
        case .live: .green
        case .notDenied: .red
        }
    }
}

extension PortRow {
    var hostText: String {
        hostPort.map { "\(hostIP):\($0)" } ?? "-"
    }

    var mapping: Project.PortMapping? {
        guard let hostPort, let sandboxPort else { return nil }
        return .init(sandboxPort: sandboxPort, hostPort: hostPort)
    }
}

/// The actions that fit a row: open or copy a published URL, deny, or remove.
/// Takes the model directly: on macOS a Table's cells are hosted separately and do not reliably
/// get an `@Observable` object from the environment (reading it there crashed).
struct PortActions: View {
    let model: AppModel
    let row: PortRow

    var body: some View {
        HStack(spacing: 8) {
            if let url = row.url, row.state == .live {
                Button("Open", systemImage: "safari") { if let target = URL(string: url) { NSWorkspace.shared.open(target) } }
                    .help("Open \(url)")
                Button("Copy", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url, forType: .string)
                }
            }
            let project = model.project(named: row.sandbox)
            switch (row.kind, row.state) {
            case (.published, _):
                Button("Remove", systemImage: "trash") { model.unpublish(row) }
                    .help("Unpublish")
            case (.hostService, .notDenied):
                if let project {
                    Button("Deny", systemImage: "hand.raised") { model.denyReserved([row], on: project) }
                        .help("Deny \(row.missingDenies.joined(separator: ", ")) for this sandbox")
                }
            case (.hostService, _):
                if let project, let port = row.hostPort {
                    Button("Remove", systemImage: "trash") { model.removeHostService(port, from: project) }
                        .help("Deny it for the sandbox")
                }
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
    }
}

struct StateLabelStyle: LabelStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 6)).foregroundStyle(color)
            configuration.title
        }
    }
}

/// One project's ports in its Info tab, and Add.
struct ProjectPortsSections: View {
    @Environment(AppModel.self) private var model
    let project: Project
    @State private var adding = false

    init(project: Project) {
        self.project = project
    }

    var body: some View {
        // sbx's global rules are on the Network page and in the rules table below.
        let rows = model.portRows().filter { $0.sandbox == project.name }
        InfoCard("Ports", systemImage: "point.3.connected.trianglepath.dotted") {
            if rows.isEmpty {
                Text("None published or allowed").foregroundStyle(.secondary)
            }
            ForEach(rows) { row in
                HStack {
                    Text(row.kind == .published
                         ? "\(row.hostPort.map { "localhost:\($0)" } ?? "sandbox") → \(row.sandboxPort.map(String.init) ?? "-")"
                         : "\(row.label.map { "\($0) " } ?? "")host \(row.hostPort.map(String.init) ?? "-")")
                        .monospacedDigit()
                    if row.state != .live {
                        Text(row.state.title).font(.caption).foregroundStyle(row.state.color)
                    }
                    Spacer()
                    PortActions(model: model, row: row)
                }
                .padding(.horizontal, 4)
                .background(row.state.differs ? Color.orange.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 4))
            }
        } actions: {
            Button("Add...", systemImage: "plus") { adding = true }
                .help("Publish a sandbox port on this Mac, or let the sandbox reach a port on this Mac")
                .popover(isPresented: $adding, arrowEdge: .bottom) {
                    NewPortPopover(model: model, project: project) { adding = false }
                }
        }
    }
}

/// Publish a sandbox port on this Mac, or let the project's sandbox reach a port on this Mac: one row.
struct NewPortPopover: View {
    enum Direction: String, CaseIterable {
        case publish = "Publish"
        case allow = "Allow"
    }

    let model: AppModel
    let project: Project
    let done: () -> Void
    @State private var direction = Direction.publish
    @State private var port = ""

    init(model: AppModel, project: Project, done: @escaping () -> Void) {
        self.model = model
        self.project = project
        self.done = done
    }

    var body: some View {
        HStack(spacing: 8) {
            Picker("Direction", selection: $direction) {
                ForEach(Direction.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help(direction == .publish ? "Sandbox port to this Mac" : "Mac port to the sandbox")
            TextField("Port", text: $port)
                .frame(width: 70)
                .onSubmit(add)
            Button("Add", action: add)
                .keyboardShortcut(.defaultAction)
                .disabled(Int(port) == nil)
        }
        .padding(12)
    }

    private func add() {
        guard let number = Int(port) else { return }
        switch direction {
        case .publish: model.publish(sandboxPort: number, on: project)
        case .allow: model.addHostService(number, to: project)
        }
        done()
    }
}

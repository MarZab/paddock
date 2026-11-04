import PaddockCore
import SwiftUI

/// The sidebar's System > Processes page, also File > Processes (backlog doc UI, Processes):
/// sbx's and Paddock's processes on this Mac in a table, by kind, with CPU, memory, and how long they
/// run. sbx tools whose terminal is gone can be stopped, after a confirmation that lists them; nothing
/// else can, and nothing outside sbx and Paddock is listed (that is Activity Monitor's).
struct SbxProcessesView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: Set<Int32> = []
    @State private var sortOrder = [KeyPathComparator(\Row.group), KeyPathComparator(\Row.cpu, order: .reverse)]
    /// The processes the operator asked to stop, waiting for the confirmation.
    @State private var toStop: [SbxProcess] = []

    struct Row: Identifiable {
        let entry: SbxProcess
        let group: Int
        let kind: String
        let title: String
        let cpu: Double
        let memory: Int
        let age: Int
        let command: String

        var id: Int32 { entry.process.pid }
        var pid: Int32 { entry.process.pid }

        init(_ entry: SbxProcess) {
            self.entry = entry
            let kind = SbxProcessText.kind(entry.kind)
            group = kind.order
            self.kind = kind.name
            title = SbxProcessText.title(entry)
            cpu = entry.process.cpuPercent
            memory = entry.process.rssKiB * 1024
            age = entry.process.elapsed
            command = entry.process.command
        }
    }

    var body: some View {
        let rows = model.hostProcesses.map(Row.init).sorted(using: sortOrder)
        let orphans = model.orphanedSbxTools
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                if orphans.isEmpty {
                    Label("Every sbx command has its terminal", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                } else {
                    Label("\(orphans.count) sbx command\(orphans.count == 1 ? " runs" : "s run") without a terminal",
                          systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                    Button("Stop Them...") { toStop = orphans }
                }
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.readHostProcesses() } }
            }
            .padding(12)
            Divider()
            Table(rows, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Kind", value: \.group) { row in
                    Text(row.kind)
                        .foregroundStyle(row.entry.kind == .orphanedTool ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                }
                .width(min: 110, ideal: 140)
                TableColumn("Process", value: \.title) { row in
                    Text(row.title).lineLimit(1)
                }
                .width(min: 140, ideal: 200)
                TableColumn("PID", value: \.pid) { row in
                    Text(String(row.pid)).monospacedDigit().foregroundStyle(.secondary)
                }
                .width(60)
                TableColumn("CPU", value: \.cpu) { row in
                    Text(String(format: "%.0f%%", row.cpu)).monospacedDigit()
                }
                .width(55)
                TableColumn("Memory", value: \.memory) { row in
                    Text(ResourceText.bytes(row.memory)).monospacedDigit()
                }
                .width(80)
                TableColumn("Running", value: \.age) { row in
                    Text(SbxProcessText.age(row.age)).monospacedDigit().foregroundStyle(.secondary)
                }
                .width(65)
                TableColumn("Command", value: \.command) { row in
                    Text(row.command).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        .help(row.command)
                }
            }
            .contextMenu(forSelectionType: Int32.self) { pids in
                let chosen = rows.filter { pids.contains($0.pid) && $0.entry.kind.isStoppable }.map(\.entry)
                Button(chosen.count > 1 ? "Stop \(chosen.count)..." : "Stop...") { toStop = chosen }
                    .disabled(chosen.isEmpty)
            }
            .overlay {
                if rows.isEmpty { ContentUnavailableView("No sbx processes", systemImage: "cpu") }
            }
            Divider()
            Text("Only sbx commands without a terminal can be stopped here. A sandbox's machine ends when the sandbox stops.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
        }
        .task { await model.readHostProcesses() }
        .confirmationDialog("Stop \(toStop.count) sbx process\(toStop.count == 1 ? "" : "es")?",
                            isPresented: Binding(get: { !toStop.isEmpty }, set: { if !$0 { toStop = [] } })) {
            Button("Stop", role: .destructive) {
                let chosen = toStop
                toStop = []
                Task { await model.stop(chosen) }
            }
        } message: {
            Text("Their terminal is gone, so nothing else will stop them:\n"
                 + toStop.map { "\($0.process.pid)  \($0.process.command)" }.joined(separator: "\n"))
        }
    }
}

/// The words for sbx's processes on the Mac. Outside the view, so building a row needs no actor.
enum SbxProcessText {
    /// The kind's place in the table and its name.
    static func kind(_ kind: SbxProcessKind) -> (order: Int, name: String) {
        switch kind {
        case .orphanedTool: (0, "No terminal")
        case .leftoverWatcher: (1, "Left by Paddock")
        case .toolInUse: (2, "In a terminal")
        case .watcher: (3, "Paddock")
        case .sandboxVM: (4, "Sandbox machine")
        case .daemon, .llmman, .helper: (5, "sbx")
        }
    }

    static func title(_ entry: SbxProcess) -> String {
        switch entry.kind {
        case .watcher, .leftoverWatcher: "Watcher " + (entry.process.command.split(separator: " ").last.map(String.init) ?? "")
        case .orphanedTool, .toolInUse: toolTitle(entry.process.command)
        case .daemon: "sbx daemon"
        case .llmman: "llmman"
        // Which sandbox a machine belongs to is not in sbx's output yet (PAD-31).
        case .sandboxVM(let id): "Machine \(id.prefix(12))"
        case .helper(let name): name
        }
    }

    /// "sbx dashboard" for a bare `sbx`, else the sbx command: "sbx exec", "sbx run".
    static func toolTitle(_ command: String) -> String {
        let verb = command.split(separator: " ").dropFirst().first { !$0.hasPrefix("-") }
        return verb.map { "sbx \($0)" } ?? "sbx dashboard"
    }

    static func age(_ seconds: Int) -> String {
        if seconds >= 86_400 { return "\(seconds / 86_400) d" }
        if seconds >= 3600 { return "\(seconds / 3600) h" }
        return "\(max(1, seconds / 60)) min"
    }
}

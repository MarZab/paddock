import PaddockCore
import SwiftUI

/// A sandbox's numbers in words (backlog doc UI, Resources).
enum ResourceText {
    static func percent(_ share: Double) -> String { "\(Int((share * 100).rounded()))%" }

    /// KiB as GB, with one decimal below 10.
    static func gigabytes(_ kib: Int) -> String {
        let value = Double(kib) / 1_048_576
        return value < 10 ? String(format: "%.1f", value) : String(Int(value.rounded()))
    }

    static func bytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .memory)
    }

    /// CPUs as Activity Monitor counts them: 100% is one CPU, 250% two and a half.
    static func cores(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
}

/// Info's Resources: the sandbox's CPU, memory, and disk, read every 5 s only while Info is shown
/// (backlog doc UI, Resources), and the way to its Processes tab.
struct SandboxResourcesSection: View {
    @Environment(AppModel.self) private var model
    let project: Project
    @State private var sample: SandboxSample?
    /// CPU use since the sample before; nil until there are two.
    @State private var cpuBusy: Double?
    @State private var problem: String?
    static let interval: Duration = .seconds(5)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Resources").font(.headline)
                Spacer()
                Button("Processes", systemImage: "cpu") { model.openProcesses(of: project) }
                    .disabled(!model.mayPoll(project))
                    .help("What runs in the sandbox, by app, in a tab of its own")
            }
            // A gray box, like Info's other sections.
            Group {
                if !model.mayPoll(project) {
                    Text("Shown while the sandbox runs.").foregroundStyle(.secondary)
                } else if let sample {
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                        meter("CPU", share: cpuBusy, text: cpuBusy.map { "\(ResourceText.percent($0)) of \(sample.cpus) CPUs" }
                              ?? "\(sample.cpus) CPUs")
                        meter("Memory", share: Self.share(sample.memoryUsedKiB, of: sample.memoryTotalKiB),
                              text: "\(ResourceText.gigabytes(sample.memoryUsedKiB)) of \(ResourceText.gigabytes(sample.memoryTotalKiB)) GB")
                        if sample.diskTotalKiB > 0 {
                            meter("Disk", share: Self.share(sample.diskUsedKiB, of: sample.diskTotalKiB),
                                  text: "\(ResourceText.gigabytes(sample.diskUsedKiB)) of \(ResourceText.gigabytes(sample.diskTotalKiB)) GB")
                        }
                        if sample.load.count == 3 {
                            GridRow {
                                Text("Load").foregroundStyle(.secondary)
                                Text(sample.load.map { String(format: "%.2f", $0) }.joined(separator: "  "))
                                    .monospacedDigit()
                                    .help("Processes waiting for a CPU on average over 1, 5, and 15 minutes; \(sample.cpus) CPUs")
                                    .gridCellColumns(2)
                            }
                        }
                    }
                } else if let problem {
                    Text(problem).foregroundStyle(.secondary).font(.callout)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .font(.callout)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        }
        .task(id: project.name) { await poll() }
    }

    private func meter(_ title: String, share: Double?, text: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            ProgressView(value: share ?? 0)
                .progressViewStyle(.linear)
                .tint(Self.color(share ?? 0))
                .frame(width: 120)
                .opacity(share == nil ? 0.3 : 1)
            Text(text).monospacedDigit()
        }
    }

    static func share(_ used: Int, of total: Int) -> Double? {
        total > 0 ? min(1, Double(used) / Double(total)) : nil
    }

    /// Green until it gets tight: orange from 75%, red from 90%.
    static func color(_ share: Double) -> Color {
        share >= 0.9 ? .red : share >= 0.75 ? .orange : .green
    }

    private func poll() async {
        while !Task.isCancelled {
            do {
                if let next = try await model.readSummary(of: project) {
                    cpuBusy = next.cpuBusy(since: sample?.cpu)
                    sample = next
                    problem = nil
                } else {
                    sample = nil
                    cpuBusy = nil
                }
            } catch {
                problem = "Could not read the sandbox: \(error)"
            }
            try? await Task.sleep(for: Self.interval)
        }
    }
}

/// The Processes tab (backlog doc UI, Resources): every process in the sandbox by app, an app with
/// several processes opening into them, with CPU over the last second and memory. Read every 5 s
/// only while the tab is shown.
struct SandboxProcessesTab: View {
    @Environment(AppModel.self) private var model
    let project: Project
    @State private var sample: SandboxSample?
    @State private var problem: String?
    @State private var sortOrder = [KeyPathComparator(\ProcessRow.cores, order: .reverse)]
    static let interval: Duration = .seconds(5)

    /// One row: an app (its processes as children when it has more than one) or a process.
    struct ProcessRow: Identifiable {
        let id: String
        let name: String
        let pid: Int32?
        let cores: Double
        let bytes: Int
        let command: String
        var children: [ProcessRow]?

        /// For sorting by PID: an app of several processes has none and sorts first.
        var pidOrder: Int32 { pid ?? 0 }

        init(app: SandboxApp) {
            id = "app:" + app.name
            name = app.processes.count > 1 ? "\(app.name) (\(app.processes.count))" : app.name
            pid = app.processes.count == 1 ? app.processes.first?.pid : nil
            cores = app.cores
            bytes = app.residentBytes
            command = app.processes.count == 1 ? app.processes.first?.command ?? "" : ""
            children = app.processes.count > 1 ? app.processes.map(ProcessRow.init(process:)) : nil
        }

        init(process: SandboxProcess) {
            id = "pid:\(process.pid)"
            name = process.name
            pid = process.pid
            cores = process.cores
            bytes = process.residentBytes
            command = process.command
            children = nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            Divider()
            if !model.mayPoll(project) {
                ContentUnavailableView("Shown while the sandbox runs", systemImage: "cpu")
            } else if let sample {
                Table(rows(sample), children: \.children, sortOrder: $sortOrder) {
                    TableColumn("App / process", value: \.name) { row in
                        Text(row.name).lineLimit(1)
                    }
                    .width(min: 140, ideal: 200)
                    TableColumn("PID", value: \.pidOrder) { row in
                        Text(row.pid.map(String.init) ?? "").monospacedDigit().foregroundStyle(.secondary)
                    }
                    .width(70)
                    TableColumn("CPU", value: \.cores) { row in
                        Text(ResourceText.cores(row.cores)).monospacedDigit()
                    }
                    .width(70)
                    TableColumn("Memory", value: \.bytes) { row in
                        Text(ResourceText.bytes(row.bytes)).monospacedDigit()
                    }
                    .width(90)
                    TableColumn("Command", value: \.command) { row in
                        Text(row.command).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                            .help(row.command)
                    }
                }
            } else if let problem {
                ContentUnavailableView("Could not read the processes", systemImage: "exclamationmark.triangle",
                                       description: Text(problem))
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: project.name) { await poll() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Processes in \(project.name)").font(.headline)
            Spacer()
            if let sample {
                if let busy = sample.cpuBusy() {
                    Text("CPU \(ResourceText.percent(busy)) of \(sample.cpus)").monospacedDigit()
                }
                Text("Memory \(ResourceText.gigabytes(sample.memoryUsedKiB)) of \(ResourceText.gigabytes(sample.memoryTotalKiB)) GB")
                    .monospacedDigit()
                Text("\(sample.processes.count) processes")
            }
        }
        .foregroundStyle(.secondary)
    }

    /// Apps sorted by the table's order, and each app's processes too.
    private func rows(_ sample: SandboxSample) -> [ProcessRow] {
        SandboxTop.apps(sample.processes).map(ProcessRow.init(app:)).sorted(using: sortOrder).map { row in
            var row = row
            row.children = row.children?.sorted(using: sortOrder)
            return row
        }
    }

    private func poll() async {
        while !Task.isCancelled {
            do {
                if let next = try await model.readProcesses(of: project) {
                    sample = next
                    problem = nil
                } else {
                    sample = nil
                }
            } catch {
                problem = String(describing: error)
            }
            try? await Task.sleep(for: Self.interval)
        }
    }
}

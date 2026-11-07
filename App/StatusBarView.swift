import AppKit
import PaddockCore
import SwiftUI

/// The status button in the sidebar's title bar, next to New Project (backlog doc UI): one dot,
/// green when every check is, yellow otherwise, that opens every check (dependencies, sbx,
/// llmman's hardening, the gateway) and the last error. It flashes red when an error arrives.
struct StatusButton: View {
    @Environment(AppModel.self) private var model
    @State private var flashing = false

    var body: some View {
        @Bindable var model = model
        Button { model.showsStatusChecks.toggle() } label: {
            ZStack {
                if let status = model.status {
                    StatusDot(status: StatusChecks.allGreen(status) ? .green : .yellow, size: 10)
                } else {
                    ProgressView().controlSize(.mini)
                }
                Circle()
                    .fill(.red)
                    .frame(width: 14, height: 14)
                    .opacity(flashing ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .frame(width: 16, height: 16)
            // sbx tools whose terminal is gone keep running unseen (backlog doc UI, Processes).
            .overlay(alignment: .topTrailing) {
                if !model.orphanedSbxTools.isEmpty {
                    Image(systemName: "exclamationmark.circle.fill").font(.system(size: 8)).foregroundStyle(.orange)
                        .background(Circle().fill(.background).padding(1))
                        .offset(x: 4, y: -3)
                        .accessibilityLabel("sbx processes without a terminal")
                }
            }
        }
        .help(help)
        .accessibilityLabel("Status checks")
        .popover(isPresented: $model.showsStatusChecks, arrowEdge: .bottom) {
            StatusChecksPopover { model.showsStatusChecks = false }
        }
        .onChange(of: model.errorCount) { flash() }
    }

    private var help: String {
        var lines: [String] = []
        if let status = model.status {
            lines.append(StatusChecks.allGreen(status) ? "Every check is green" : StatusChecks.summary(status))
        } else {
            lines.append("Checking...")
        }
        if let lastError = model.lastError {
            lines.append("Last error: \(lastError.split(separator: "\n").first.map(String.init) ?? lastError)")
        }
        let orphans = model.orphanedSbxTools.count
        if orphans > 0 {
            lines.append("\(orphans) sbx process\(orphans == 1 ? "" : "es") without a terminal (System > Processes)")
        }
        return lines.joined(separator: "\n")
    }

    /// Three red pulses.
    private func flash() {
        Task {
            for _ in 0..<3 {
                withAnimation(.easeIn(duration: 0.15)) { flashing = true }
                try? await Task.sleep(for: .milliseconds(350))
                withAnimation(.easeOut(duration: 0.25)) { flashing = false }
                try? await Task.sleep(for: .milliseconds(350))
            }
        }
    }
}

/// The running build's version next to the status button (backlog doc UI, Version): `yymmdd.N`,
/// with the commit in the tooltip. Selectable, so it can be pasted into a ticket.
struct VersionLabel: View {
    private static let current = AppVersion(info: Bundle.main.infoDictionary ?? [:])

    var body: some View {
        Text(Self.current.label)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .help(Self.current.help)
            .accessibilityLabel("Version \(Self.current.label)")
    }
}

enum StatusChecks {
    static func allGreen(_ status: PaddockStatus) -> Bool {
        guard case .running = status.sbx else { return false }
        return status.missingDependencies.isEmpty && status.llmman.overall == .green
    }

    static func summary(_ status: PaddockStatus) -> String {
        var issues = status.llmman.checks.filter { $0.status != .green }.count + status.missingDependencies.count
        if case .running = status.sbx {} else { issues += 1 }
        if status.llmman.checks.isEmpty { issues += 1 }  // nothing observed counts as red
        return "\(issues) need\(issues == 1 ? "s" : "") attention"
    }
}

/// Every check behind the status button, with what can be done about them, and the last error.
struct StatusChecksPopover: View {
    @Environment(AppModel.self) private var model
    let close: () -> Void
    @State private var confirmsClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let lastError = model.lastError {
                group("Last error") {
                    Text(lastError)
                        .foregroundStyle(.red)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            if let status = model.status {
                group("Dependencies") {
                    ForEach(status.dependencies) { report in
                        DependencyRow(report: report)
                    }
                    if !status.missingDependencies.isEmpty {
                        Text("Paddock does not install anything. Run the example command in your own terminal, then check again.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                group("sbx") {
                    sbx(status.sbx)
                    switch status.sbxReadSource {
                    case .socket(let apiVersion):
                        row(.green, "Reads", "sandboxd socket (API \(apiVersion))")
                    case .unsupportedAPI(let found):
                        row(.yellow, "Reads", "sbx CLI: sbx was updated (API \(found)) and Paddock does not know its socket yet. "
                            + "Capture it with: mise run capture:socket proxy --swap")
                    case .cli(let reason):
                        // Still correct, only slower: every read starts sbx.
                        row(.yellow, "Reads", "sbx CLI; the socket failed: \(reason)")
                    case nil:
                        EmptyView()
                    }
                }
                group("llmman") {
                    ForEach(status.llmman.checks, id: \.kind) { check in
                        row(check.status, check.kind.title, check.detail)
                    }
                    if let loaded = status.loadedModels {
                        row(.green, "Loaded models", "\(loaded)")
                    }
                    if status.llmman.check(.promptHistory)?.status == .yellow {
                        Button("Clear prompt history...") { confirmsClear = true }
                    }
                }
                group("Gateway") {
                    let listening = model.gatewayPorts.count
                    row(.green, "Listeners", listening == 0 ? "idle" : "\(listening) listening")
                }
            } else {
                Text("Checking...").foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Button("Crash Reports") {
                    close()
                    model.revealCrashReports()
                }
                .help("Show macOS's crash reports in Finder, with Paddock's newest one selected")
                Spacer()
                if model.isRefreshing {
                    ProgressView().controlSize(.small)
                }
                // Always available: a check that is stuck is replaced by a new one.
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.checkAgain() } }
                    .help("Run every check again and read sbx's sandboxes, ports, and rules again")
            }
        }
        .font(.callout)
        .padding(14)
        .frame(width: 420)
        .confirmationDialog("Clear llmman's saved prompts?", isPresented: $confirmsClear) {
            Button("Clear", role: .destructive) { model.clearPromptHistory() }
        } message: {
            Text("llmman saves the last message of every request, including agent requests, in prompts.jsonl.")
        }
    }

    private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
    }

    private func row(_ status: LlmmanHealth.Status, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            StatusDot(status: status)
            Text(title)
            Spacer()
            Text(detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder private func sbx(_ state: PaddockStatus.Sbx) -> some View {
        switch state {
        case .running(let version, let sandboxes, let running):
            row(.green, "sbx \(version)", "\(running) of \(sandboxes) running")
        case .daemonStopped(let version):
            row(.red, "sbx \(version)", "daemon stopped; start it in a terminal: sbx daemon start")
        case .unavailable(let reason):
            row(.red, "sbx unavailable", reason)
        }
    }
}

struct StatusDot: View {
    let status: LlmmanHealth.Status
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .accessibilityLabel(label)
    }

    private var color: Color {
        switch status {
        case .green: .green
        case .yellow: .yellow
        case .red: .red
        }
    }

    private var label: String {
        switch status {
        case .green: "ok"
        case .yellow: "warning"
        case .red: "failing"
        }
    }
}

/// One dependency Paddock needs (backlog doc Overview, Dependencies are the operator's job): its state, and
/// when it is missing, the example command to copy and run in a terminal.
private struct DependencyRow: View {
    let report: DependencyReport

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: report.isSatisfied ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(report.isSatisfied ? .green : .red)
                Text(report.dependency.displayName).bold()
                Spacer()
                Text(stateText).foregroundStyle(.secondary)
            }
            if let path = report.path {
                Text(path).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            if !report.isSatisfied {
                HStack {
                    Text(report.dependency.exampleInstall)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                    Spacer()
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(report.dependency.exampleInstall, forType: .string)
                    }
                }
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private var stateText: String {
        switch report.state {
        case .ok(let version): version
        case .missing: "not found"
        case .tooOld(let found): "\(found), needs \(report.dependency.minimumVersion) or newer"
        case .unknownVersion(let reason): reason
        }
    }
}

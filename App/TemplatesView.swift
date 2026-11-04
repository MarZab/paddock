import PaddockCore
import SwiftUI

/// The sidebar's System > Templates page (backlog doc UI, Templates): sbx's template images in a
/// table with what uses them, as far as Paddock knows (sbx does not report a sandbox's image), and
/// removing the chosen ones after a confirmation that lists them.
struct TemplatesView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: Set<String> = []
    @State private var sortOrder = [KeyPathComparator(\Row.group), KeyPathComparator(\Row.name)]
    /// The images the operator asked to remove, waiting for the confirmation.
    @State private var toRemove: [TemplateRow] = []

    struct Row: Identifiable {
        let entry: TemplateRow
        let group: Int
        let kind: String
        let name: String
        let flavor: String
        let size: Int64
        let created: Date
        let usedBy: String

        var id: String { entry.id }

        init(_ entry: TemplateRow) {
            self.entry = entry
            switch entry.kind {
            case .kitAssembled:
                group = 2
                kind = "Assembled kits"
            case .oldProjectImage:
                group = 0
                kind = "Old project image"
            case .other:
                group = 1
                kind = "Other"
            case .kitBuild:
                group = entry.isOlderBuild ? 0 : 2
                kind = entry.isOlderBuild ? "Older kit build" : "Kit build"
            case .agentTemplate:
                group = 3
                kind = "Agent template"
            }
            name = entry.name
            flavor = entry.template.flavor ?? ""
            size = entry.template.size
            created = entry.template.createdAt
            usedBy = entry.usedBy
        }
    }

    var body: some View {
        let all = model.templates ?? []
        let rows = all.map(Row.init).sorted(using: sortOrder)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("\(all.count) images, \(TemplatesText.bytes(TemplateUsage.size(of: all)))")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Remove...") { toRemove = removable(selection, in: all) }
                    .disabled(removable(selection, in: all).isEmpty)
                    .help("Remove the selected images from sbx")
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.readTemplates() } }
            }
            .padding(12)
            Divider()
            Table(rows, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Kind", value: \.group) { row in
                    Text(row.kind).foregroundStyle(.secondary)
                }
                .width(min: 90, ideal: 110)
                TableColumn("Image", value: \.name) { row in
                    Text(row.name).lineLimit(1).truncationMode(.middle).help(row.name)
                }
                .width(min: 160, ideal: 280)
                TableColumn("Agent", value: \.flavor) { row in
                    Text(row.flavor).foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 130)
                TableColumn("Size", value: \.size) { row in
                    Text(TemplatesText.bytes(row.size)).monospacedDigit()
                }
                .width(70)
                TableColumn("Created", value: \.created) { row in
                    Text(row.created, format: .dateTime.year().month().day()).monospacedDigit().foregroundStyle(.secondary)
                }
                .width(90)
                TableColumn("Used by", value: \.usedBy) { row in
                    Text(row.usedBy).lineLimit(1)
                        .help(row.entry.removalNote)
                }
            }
            .contextMenu(forSelectionType: String.self) { ids in
                let chosen = removable(ids, in: all)
                Button(chosen.count > 1 ? "Remove \(chosen.count)..." : "Remove...") { toRemove = chosen }
                    .disabled(chosen.isEmpty)
            }
            .overlay {
                if model.templates == nil {
                    ProgressView("Reading sbx's templates")
                } else if rows.isEmpty {
                    ContentUnavailableView("No templates", systemImage: "shippingbox")
                }
            }
            Divider()
            Text("sbx does not say which image a sandbox runs: \"Used by\" is what each image is for, from its name.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
        }
        .task { await model.readTemplates() }
        .confirmationDialog(TemplatesText.title(toRemove),
                            isPresented: Binding(get: { !toRemove.isEmpty }, set: { if !$0 { toRemove = [] } })) {
            Button("Remove", role: .destructive) {
                let chosen = toRemove
                toRemove = []
                selection = []
                Task { await model.removeTemplates(chosen) }
            }
        } message: {
            Text(TemplatesText.message(toRemove))
        }
    }

    /// The chosen images that may be removed now.
    private func removable(_ ids: Set<String>, in rows: [TemplateRow]) -> [TemplateRow] {
        rows.filter { ids.contains($0.id) }
    }
}

/// The words for the Templates page. Outside the view, so building them needs no actor.
enum TemplatesText {
    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    static func title(_ rows: [TemplateRow]) -> String {
        "Remove \(rows.count) image\(rows.count == 1 ? "" : "s") (\(bytes(TemplateUsage.size(of: rows))))?"
    }

    /// At most `TemplateUsage.confirmationLimit` images, then the rest summed up, so the dialog
    /// fits the screen (PAD-80).
    static func message(_ rows: [TemplateRow]) -> String {
        let (named, more) = TemplateUsage.confirmationList(rows)
        var lines = named.map { "\($0.name), \(bytes($0.template.size)): \($0.removalNote)." }
        if !more.isEmpty {
            lines.append("And \(more.count) more (\(bytes(TemplateUsage.size(of: more)))).")
        }
        return lines.joined(separator: "\n")
    }
}

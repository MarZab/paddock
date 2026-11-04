import PaddockCore
import SwiftUI

/// The kits paddock.yaml offers for an agent, each with a checkbox (backlog doc Kits). Selecting a
/// kit selects what it needs; unselecting one unselects what builds on it. The kit field adds a
/// catalog kit to `project`'s sbxenv.yaml when it has one, anything else to paddock.yaml.
struct KitPicker: View {
    @Environment(AppModel.self) private var model
    let app: AppConfig
    let agent: AppConfig.Agent?
    var project: Project?
    @Binding var selection: [String]

    var body: some View {
        ForEach(offered, id: \.self) { name in
            if let kit = app.kits[name] {
                Toggle(isOn: Binding(get: { selection.contains(name) }, set: { set(name, $0) })) {
                    label(name, summary: kit.summary, source: kit.sourceDescription, needs: kit.needs)
                }
            }
        }
        HStack {
            TextField("Add a kit", text: $newKit, prompt: Text("mise, or docker.io/acme/tools-kit@sha256:..."))
                .onSubmit(addKit)
            Button("Add", action: addKit)
                .disabled(newKit.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .help(addHelp)
        if let addProblem {
            Text(addProblem).font(.callout).foregroundStyle(.red)
        }
        if let addedToFile {
            Text(addedToFile).font(.callout).foregroundStyle(.secondary)
        }
    }

    @State private var newKit = ""
    @State private var addProblem: String?
    @State private var addedToFile: String?

    private var addHelp: String {
        guard let project, model.environment(of: project) != nil else {
            return "An sbx kit's name from docker/sbx-kits-contrib, or anything sbx create --kit takes. It is added to paddock.yaml and selected."
        }
        return "An sbx kit's name from docker/sbx-kits-contrib (or a docker.io/sbx/ reference) is added to the project's sbxenv.yaml. "
            + "Anything else sbx create --kit takes is added to paddock.yaml and selected."
    }

    private func addKit() {
        do {
            switch try model.addKit(newKit, for: project) {
            case .paddock(let name):
                set(name, true)
                addedToFile = nil
            case .projectFile(let reference):
                addedToFile = "Added \(reference) to sbxenv.yaml; confirm the file, then recreate the sandbox to get it."
            }
            newKit = ""
            addProblem = nil
        } catch {
            addProblem = String(describing: error)
        }
    }

    /// Paddock's own kits first, then the others by name.
    private var offered: [String] {
        app.kits.filter { agent.map($0.value.isOffered(for:)) ?? true }
            .sorted { a, b in
                let builtinA = if case .builtin = a.value.source { true } else { false }
                let builtinB = if case .builtin = b.value.source { true } else { false }
                return builtinA != builtinB ? builtinA : a.key < b.key
            }
            .map(\.key)
    }

    private func set(_ name: String, _ selected: Bool) {
        selection = selected ? KitSelection.withNeeds(selection + [name], app: app).sorted()
            : KitSelection.removing(name, from: selection, app: app)
    }

    private func label(_ name: String, summary: String, source: String, needs: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
            if !summary.isEmpty {
                Text(summary).font(.callout).foregroundStyle(.secondary)
            }
            Text(needs.isEmpty ? source : "\(source), needs \(needs.joined(separator: ", "))")
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(source)
        }
    }
}

/// What the kit sections say about kits in general, under the picker.
struct KitsFootnote: View {
    var body: some View {
        Text("""
            Kits install in the sandbox when it is created and add their own network rules ("kit" on the \
            Network page). Kits you add here go into paddock.yaml under kits:, or sbx's own kits into the \
            project's sbxenv.yaml when it has one.
            """)
    }
}

/// Changes an existing project's kits (from its Info tab). sbx applies kits only at create, so an
/// existing sandbox shows "recreate" under Needs attention afterwards.
struct KitsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let project: Project
    @State private var selection: [String] = []

    var body: some View {
        let agent = model.appConfig.agents[project.agent]
        VStack(spacing: 0) {
            Form {
                Section {
                    KitPicker(app: model.appConfig, agent: agent, project: project, selection: $selection)
                } header: {
                    Text("Kits for \(project.name)").font(.title3.bold())
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        KitsFootnote()
                        if model.state(of: project) != nil {
                            Text("The sandbox gets the new kits when it is recreated.")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    model.setKits(selection, for: project)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection.sorted() == project.chosenKits(model.appConfig).sorted())
            }
            .padding(12)
        }
        .frame(width: 540, height: 520)
        .onAppear { selection = project.chosenKits(model.appConfig) }
    }
}

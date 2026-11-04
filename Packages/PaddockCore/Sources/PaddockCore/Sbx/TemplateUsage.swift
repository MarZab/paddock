import Foundation

/// One of sbx's template images on the Templates page (backlog doc UI, Templates), with what it
/// is for. sbx does not report which image a sandbox runs; since PAD-73.4 Paddock builds no images
/// of its own (sbx builds a project kit's itself), so what an image is comes from its name.
public struct TemplateRow: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        /// An agent's image (`docker/sandbox-templates:`, sbx's own `sbx/`, Docker's `docker/sbx-kit-`):
        /// what sbx starts that agent's sandboxes from, downloaded again when needed.
        case agentTemplate
        /// `sbx-kit-src:<kit>-<hash>`: a local kit sbx built at a create, built again when needed.
        case kitBuild
        /// `library/sandbox-kit-assembled:<hash>-kit-<n>`: the image sbx assembles from an agent's
        /// image and a sandbox's kits, built again when needed.
        case kitAssembled
        /// `paddock/<name>:<hash>`: a project image from Paddock's own builds before PAD-73.4;
        /// nothing uses it any more.
        case oldProjectImage
        /// Anything else loaded into sbx.
        case other
    }

    public let template: SbxTemplate
    /// `repository:tag` without `docker.io/`, as `sbx template rm` takes it.
    public let name: String
    public let kind: Kind
    /// A kit build with a newer build of the same kit next to it: the kit changed since, so
    /// nothing will start from this one again.
    public var isOlderBuild = false

    public var id: String { name + "@" + template.id }

    /// What uses it, in a few words.
    public var usedBy: String {
        switch kind {
        case .agentTemplate: "new \(template.flavor ?? template.tag) sandboxes"
        case .kitBuild: isOlderBuild ? "nothing (an older build of this kit)" : "a local kit sbx built"
        case .kitAssembled: "a sandbox's kits assembled by sbx"
        case .oldProjectImage: "nothing (Paddock's earlier image builds)"
        case .other: "not known"
        }
    }

    /// What removing it means, for the confirmation.
    public var removalNote: String {
        switch kind {
        case .agentTemplate: "sbx downloads it again for new \(template.flavor ?? template.tag) sandboxes"
        case .kitBuild where isOlderBuild: "a newer build of the kit exists; nothing uses this one"
        case .kitBuild: "sbx builds the kit again at the next create that names it"
        case .kitAssembled: "sbx assembles it again at the next create that needs it"
        case .oldProjectImage: "nothing uses it"
        case .other: "Paddock does not know what uses it"
        }
    }

    var sortGroup: Int {
        switch kind {
        case .oldProjectImage: 0
        case .other: 1
        case .kitBuild: 2
        case .kitAssembled: 2
        case .agentTemplate: 3
        }
    }
}

public enum TemplateUsage {
    public static func rows(_ templates: [SbxTemplate]) -> [TemplateRow] {
        var built = templates.map { template in
            let name = Self.name(of: template)
            let kind: TemplateRow.Kind
            if name.hasPrefix("docker/sandbox-templates:") || name.hasPrefix("sbx/") || name.hasPrefix("docker/sbx-kit-") {
                kind = .agentTemplate
            } else if name.hasPrefix("library/sandbox-kit-assembled:") {
                kind = .kitAssembled
            } else if name.hasPrefix("sbx-kit-src:") {
                kind = .kitBuild
            } else if name.hasPrefix("paddock/") {
                kind = .oldProjectImage
            } else {
                kind = .other
            }
            return TemplateRow(template: template, name: name, kind: kind)
        }
        // A kit's tag is `<kit>-<hash>`: all but the newest build of a kit are older ones.
        let newest = Dictionary(grouping: built.indices.filter { built[$0].kind == .kitBuild }, by: { kitName(of: built[$0]) })
            .compactMapValues { $0.max { built[$0].template.createdAt < built[$1].template.createdAt } }
        for (_, index) in newest {
            for other in built.indices where other != index && built[other].kind == .kitBuild
                && kitName(of: built[other]) == kitName(of: built[index]) {
                built[other].isOlderBuild = true
            }
        }
        return built
        .sorted { ($0.sortGroup, $0.name) < ($1.sortGroup, $1.name) }
    }

    /// The kit of an `sbx-kit-src:<kit>-<hash>` image.
    static func kitName(of row: TemplateRow) -> String {
        let tag = row.template.tag
        guard let dash = tag.lastIndex(of: "-") else { return tag }
        return String(tag[..<dash])
    }

    /// `repository:tag` without `docker.io/`.
    static func name(of template: SbxTemplate) -> String {
        let repository = template.repository.hasPrefix("docker.io/") ? String(template.repository.dropFirst(10)) : template.repository
        return repository + ":" + template.tag
    }

    /// The bytes the rows take, for the page's total and the confirmation.
    public static func size(of rows: [TemplateRow]) -> Int64 {
        rows.reduce(0) { $0 + $1.template.size }
    }

    /// The removal confirmation lists this many images; the rest are summed up, so it fits the
    /// screen however many were chosen (PAD-80).
    public static let confirmationLimit = 8

    /// The images a removal confirmation names, and the ones it only counts.
    public static func confirmationList(_ rows: [TemplateRow], limit: Int = confirmationLimit) -> (named: [TemplateRow], more: [TemplateRow]) {
        // One summed-up line in place of a single image saves nothing.
        let shown = rows.count > limit + 1 ? limit : rows.count
        return (Array(rows.prefix(shown)), Array(rows.dropFirst(shown)))
    }

    /// `sbx template rm`: `--force` because sbx asks for confirmation on a terminal Paddock does
    /// not have (backlog doc UI, Templates); Paddock asked already.
    static func removeArguments(_ name: String) -> [String] {
        ["template", "rm", "--force", name]
    }
}

/// What `ProjectRunner.removeTemplates` did.
public struct TemplateRemoval: Sendable, Equatable {
    public struct Failure: Sendable, Equatable {
        public let name: String
        /// Refused by the fresh check, gone already, or sbx's error.
        public let reason: String
    }

    public var removed: [String] = []
    public var failed: [Failure] = []
}


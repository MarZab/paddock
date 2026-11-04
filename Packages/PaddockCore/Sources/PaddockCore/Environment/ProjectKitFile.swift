import Foundation

/// The kit field's catalog kits go to the project's own `sbxenv.yaml`, so `sbx env run` gets them
/// too; custom kits go to paddock.yaml (`AppConfigFile.addKit`) (backlog doc Kits, Adding a kit).
/// The file is the project's and hand-edited, so the kit is inserted as text and everything else
/// stays as it is, comments too. The change counts like any edit: the operator confirms the file
/// again, and the sandbox gets the kit when it is created again.
public enum ProjectKitFile {
    public enum Problem: Error, Equatable, CustomStringConvertible {
        /// `kits:` is written in a form Paddock does not insert into (`kits: [a, b]` on one line, say).
        case kitsNotABlock
        /// The file does not read any more after the insertion (Paddock never writes that).
        case unreadable(String)

        public var description: String {
            switch self {
            case .kitsNotABlock: "kits: in sbxenv.yaml is not a block list; add the kit by hand"
            case .unreadable(let problem): "sbxenv.yaml would not read after adding the kit: \(problem)"
            }
        }
    }

    /// The reference a project file names for the kit field's `text`, when it is one of sbx's
    /// catalog kits: a contrib kit's name (`mise`) or a `docker.io/sbx/...` reference. Nil for
    /// anything else (a custom kit, for paddock.yaml).
    public static func catalogReference(_ text: String) -> String? {
        guard let (name, source) = try? Kit.parseInput(text) else { return nil }
        let reference = source ?? Kit.contribReference(name)
        return ProjectEnvironment.isCatalog(reference) ? reference : nil
    }

    /// Adds `reference` to the `sbxenv.yaml` in `folder`, unless it lists it already. Returns
    /// whether the file changed.
    @discardableResult
    public static func add(_ reference: String, folder: String) throws -> Bool {
        let path = folder + "/" + SbxEnvFile.fileName
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let file = try SbxEnvFile.load(from: data)
        guard !file.kits.contains(where: { $0.source == reference }) else { return false }
        let text = try inserting(reference, into: String(decoding: data, as: UTF8.self))
        do throws(SbxEnvFileError) {
            _ = try SbxEnvFile.load(from: Data(text.utf8))
        } catch {
            throw Problem.unreadable(error.description)
        }
        try Data(text.utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
        return true
    }

    /// `text` with `- "reference"` at the end of its top-level `kits:` block list, indented like
    /// the entries there, or a new `kits:` block at the end. Lines are only added, never changed.
    static func inserting(_ reference: String, into text: String) throws(Problem) -> String {
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        let isTopLevel = { (line: String) in
            guard let first = line.first else { return false }
            return first != " " && first != "\t" && first != "#"
        }
        let item = PaddockOverlay.quoted(reference)
        guard let kitsLine = lines.firstIndex(where: { $0.hasPrefix("kits:") }) else {
            if lines.last.map({ !$0.isEmpty }) ?? false { lines.append("") }
            lines += ["kits:", "  - \(item)"]
            return lines.joined(separator: "\n") + "\n"
        }
        let rest = lines[kitsLine].dropFirst("kits:".count).trimmingCharacters(in: .whitespaces)
        guard rest.isEmpty || rest.hasPrefix("#") else { throw .kitsNotABlock }
        // The block ends before the next top-level key; insert after its last indented line, with
        // the indentation of its first entry (a list may also sit at column 0 under its key).
        var end = kitsLine
        var indent: String?
        var index = kitsLine + 1
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") || trimmed == "-" {
                if indent == nil { indent = String(line.prefix { $0 == " " }) }
            } else if isTopLevel(line) {
                break
            }
            if !trimmed.isEmpty, !trimmed.hasPrefix("#") { end = index }
            index += 1
        }
        lines.insert("\(indent ?? "  ")- \(item)", at: end + 1)
        return lines.joined(separator: "\n") + "\n"
    }
}

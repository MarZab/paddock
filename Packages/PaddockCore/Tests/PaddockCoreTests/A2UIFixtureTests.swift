import Foundation
@testable import PaddockCore
import Testing

/// PAD-146.1: the A2UI v1.0 fixtures interactive tabs are built on (`Fixtures/a2ui/README.md`):
/// upstream examples and spec cases, two files written for Paddock, and what A2UI's own Swift core
/// sent back (`mise run capture:a2ui`). These tests only check that the corpus is what later code
/// may rely on: every file decodes, every message is v1.0 of a known kind, and the basic catalog's
/// components, functions, and media URLs are all covered.
@Suite("A2UI fixtures")
struct A2UIFixtureTests {
    static let catalogID = "https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json"
    static let agentKinds: Set<String> = [
        "createSurface", "updateComponents", "updateDataModel", "deleteSurface",
        "callRendererFunction", "agentFunctionResponse",
    ]
    static let rendererKinds: Set<String> = ["action", "error", "callAgentFunction", "rendererFunctionResponse"]

    func folder(_ path: String) throws -> URL {
        guard let url = Bundle.module.url(forResource: "a2ui", withExtension: nil, subdirectory: nil) else {
            throw FixtureError.missing("a2ui")
        }
        return url.appendingPathComponent(path)
    }

    func files(_ path: String, _ suffix: String) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: folder(path), includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix(suffix) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func json(_ url: URL) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }

    /// One message per non-empty line.
    func lines(_ url: URL) throws -> [JSONValue] {
        try String(decoding: Data(contentsOf: url), as: UTF8.self)
            .split(separator: "\n")
            .map { try JSONDecoder().decode(JSONValue.self, from: Data($0.utf8)) }
    }

    /// The messages of an example file (`{name, description, messages}`).
    func messages(_ url: URL) throws -> [JSONValue] {
        guard case .array(let list)? = try json(url)["messages"] else {
            Issue.record("\(url.lastPathComponent) has no messages")
            return []
        }
        return list
    }

    /// Every agent-to-renderer message the fixtures hold.
    func agentMessages() throws -> [(file: String, message: JSONValue)] {
        let examples = try files("examples", ".json") + files("agent", ".json")
        let streams = try files("agent", ".jsonl")
        return try examples.flatMap { url in try messages(url).map { (url.lastPathComponent, $0) } }
            + streams.flatMap { url in try lines(url).map { (url.lastPathComponent, $0) } }
    }

    /// The one key besides `version`, which says what the message is.
    func kind(_ message: JSONValue) -> String? {
        guard case .object(let object) = message else { return nil }
        let keys = object.keys.filter { $0 != "version" }
        return keys.count == 1 ? keys.first : nil
    }

    /// Every object in `value`, depth first.
    func objects(_ value: JSONValue) -> [[String: JSONValue]] {
        switch value {
        case .object(let object): return [object] + object.values.flatMap { objects($0) }
        case .array(let array): return array.flatMap { objects($0) }
        default: return []
        }
    }

    @Test func everyAgentMessageIsVersionOneOfAKnownKind() throws {
        let all = try agentMessages()
        #expect(try files("examples", ".json").count == 43)
        #expect(all.count > 100)
        for (file, message) in all {
            #expect(message["version"]?.stringValue == "1.0", "\(file)")
            #expect(kind(message).map(Self.agentKinds.contains) == true, "\(file): \(String(describing: kind(message)))")
        }
        #expect(Set(all.compactMap { kind($0.message) }) == Self.agentKinds)
    }

    @Test func everySurfaceUsesTheBasicCatalog() throws {
        let created = try agentMessages().compactMap { $0.message["createSurface"] }
        #expect(!created.isEmpty)
        for surface in created {
            #expect(surface["catalogId"]?.stringValue == Self.catalogID)
        }
        #expect(try json(folder("catalog.json"))["catalogId"]?.stringValue == Self.catalogID)
    }

    @Test func coverEveryBasicComponentAndFunction() throws {
        guard case .object(let catalog) = try json(folder("catalog.json")),
              case .object(let components)? = catalog["components"],
              case .object(let functions)? = catalog["functions"] else {
            Issue.record("catalog.json has no components or functions")
            return
        }
        #expect(components.count == 18)
        #expect(functions.count == 14)
        let used = try agentMessages().flatMap { objects($0.message) }
        let usedComponents = Set(used.compactMap { $0["component"]?.stringValue })
        let usedFunctions = Set(used.compactMap { $0["@call"]?.stringValue })
        #expect(Set(components.keys).subtracting(usedComponents).isEmpty, "unused: \(Set(components.keys).subtracting(usedComponents))")
        #expect(Set(functions.keys).subtracting(usedFunctions).isEmpty, "unused: \(Set(functions.keys).subtracting(usedFunctions))")
    }

    @Test func mediaCoversEverySourceKind() throws {
        let media = try messages(folder("agent/media.json")).flatMap { objects($0) }
            .filter { ["Image", "Video", "AudioPlayer"].contains($0["component"]?.stringValue ?? "") }
        let urls = media.compactMap { $0["url"]?.stringValue } + media.compactMap { $0["posterUrl"]?.stringValue }
        #expect(Set(media.compactMap { $0["component"]?.stringValue }) == ["Image", "Video", "AudioPlayer"])
        #expect(urls.contains { $0.hasPrefix("https://") })
        #expect(urls.contains { $0.hasPrefix("data:image/") })
        #expect(urls.contains { $0.hasPrefix("data:audio/") })
        #expect(urls.contains { !$0.contains(":") })
        // A URL bound to the data model, resolved only when the tab draws it.
        #expect(media.contains { $0["url"]?["@path"] != nil })
    }

    @Test func everyRendererMessageIsVersionOneOfAKnownKind() throws {
        let actions = try lines(folder("renderer/actions.jsonl"))
        let checks = try lines(folder("renderer/checks.jsonl"))
        let errors = try lines(folder("renderer/errors.jsonl"))
        let calls = try lines(folder("renderer/calls.jsonl")) + lines(folder("renderer/library-calls.jsonl"))
        #expect(actions.count >= 30)
        #expect(checks.count >= 2)
        #expect(errors.count == 5)
        for message in actions { #expect(kind(message) == "action") }
        for message in checks + errors { #expect(kind(message) == "error") }
        let all = actions + checks + errors + calls
        #expect(Set(all.compactMap(kind)) == Self.rendererKinds)
        for message in all where kind(message) != "error" {
            #expect(message["version"]?.stringValue == "1.0")
        }
    }

    @Test func actionsCarryWhatTheAgentNeeds() throws {
        for message in try lines(folder("renderer/actions.jsonl")) {
            let action = message["action"]
            #expect(action?["name"]?.stringValue?.isEmpty == false)
            #expect(action?["surfaceId"]?.stringValue?.isEmpty == false)
            #expect(action?["sourceComponentId"]?.stringValue?.isEmpty == false)
            #expect(action?["timestamp"]?.stringValue?.hasSuffix("Z") == true)
            if case .object = action?["context"] {} else { Issue.record("no context object: \(message)") }
        }
        // The values the operator typed come back in the context the agent bound.
        let login = try lines(folder("renderer/actions.jsonl")).first { $0["action"]?["name"]?.stringValue == "login" }
        #expect(login?["action"]?["context"]?["email"]?.stringValue == "ann@example.com")
    }

    /// A press whose button checks fail never becomes an action: the agent gets the check's message.
    @Test func failedButtonChecksReachTheAgentAsErrors() throws {
        for error in try lines(folder("renderer/checks.jsonl")).compactMap({ $0["error"] }) {
            #expect(error["code"]?.stringValue == "VALIDATION_FAILED")
            #expect(error["path"]?.stringValue?.isEmpty == false)
            #expect(error["message"]?.stringValue?.isEmpty == false)
        }
        let login = try lines(folder("renderer/checks.jsonl")).first { $0["error"]?["path"]?.stringValue == "login_btn" }
        #expect(login?["error"]?["message"]?.stringValue == "Please fix errors before signing in")
    }

    @Test func errorsNameACodeAndASurface() throws {
        let errors = try lines(folder("renderer/errors.jsonl")).compactMap { $0["error"] }
        #expect(Set(errors.compactMap { $0["code"]?.stringValue })
            == ["CATALOG_NOT_FOUND", "UNKNOWN_COMPONENT_TYPE", "INTEGRITY_ERROR", "VALIDATION_FAILED"])
        for error in errors {
            #expect(error["surfaceId"]?.stringValue?.isEmpty == false)
            #expect(error["message"]?.stringValue?.isEmpty == false)
        }
    }
}

import Foundation
import Testing
@testable import PaddockCore

@Suite("llmman JSON fixtures")
struct LlmmanModelsTests {
    @Test func version() throws {
        let version = try Fixture.decode(LlmmanVersion.self, "llmman", "version.json")
        #expect(version.exe.hasSuffix("Sbx.app/Contents/MacOS/llmman"))
        #expect(version.semanticVersion == SemanticVersion(0, 1, 571))
    }

    @Test func tags() throws {
        #expect(try Fixture.decode(LlmmanTags.self, "llmman", "tags-empty.json").models.isEmpty)
        let model = try #require(try Fixture.decode(LlmmanTags.self, "llmman", "tags.json").models.first)
        #expect(model.name == "hf.co/unsloth/Qwen3.5-0.8B-GGUF:latest")
        #expect(model.details.format == "gguf")
        #expect(model.details.quantizationLevel == "Q4_K_M")
    }

    @Test func loadedModels() throws {
        #expect(try Fixture.decode(LlmmanLoaded.self, "llmman", "ps-empty.json").models.isEmpty)
    }

    @Test func node() throws {
        let node = try Fixture.decode(LlmmanNode.self, "llmman", "node.json")
        #expect(node.memory == 68_719_476_736)
    }

    @Test func shellStatusIsOff() throws {
        let status = try Fixture.decode(LlmmanShellStatus.self, "llmman", "shell-status.json")
        #expect(status == LlmmanShellStatus(enabled: false, reason: "LLMMAN_SHELL is off"))
    }
}

@Suite("SemanticVersion")
struct SemanticVersionTests {
    @Test(arguments: [
        ("v0.49.2", SemanticVersion(0, 49, 2)),
        ("0.1.571 (d76ad9e)", SemanticVersion(0, 1, 571)),
        ("1.2", SemanticVersion(1, 2, 0)),
    ])
    func parses(text: String, expected: SemanticVersion) {
        #expect(SemanticVersion(parsing: text) == expected)
    }

    @Test(arguments: ["", "vx", "nightly"])
    func rejects(text: String) {
        #expect(SemanticVersion(parsing: text) == nil)
    }

    @Test func orders() {
        #expect(SemanticVersion(0, 48, 0) < SemanticVersion(0, 49, 2))
        #expect(SemanticVersion(0, 9, 9) < SemanticVersion(0, 48, 0))
    }
}

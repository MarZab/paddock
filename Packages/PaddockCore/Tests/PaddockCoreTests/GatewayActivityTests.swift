import Foundation
import Testing
@testable import PaddockCore

struct GatewayActivityTests {
    private func entry(_ project: String, status: Int = 200, at seconds: TimeInterval = 0,
                       input: Int? = nil, output: Int? = nil) -> GatewayLogEntry {
        GatewayLogEntry(
            date: Date(timeIntervalSince1970: seconds), project: project, route: "/v1/messages", status: status,
            requestBytes: 10, responseBytes: 20, duration: .milliseconds(5), inputTokens: input, outputTokens: output
        )
    }

    @Test func summarizesOneProject() {
        let entries = [
            entry("a", input: 100, output: 20),
            entry("a", status: 429),
            entry("b", status: 500, input: 7, output: 7)
        ]
        let first = GatewayActivity.summarize(entries, project: "a")
        #expect(first.requests == 2)
        #expect(first.errors == 1)
        #expect(first.inputTokens == 100)
        #expect(first.outputTokens == 20)
        #expect(GatewayActivity.summarize(entries).requests == 3)
    }

    @Test func emptyLogIsZero() {
        #expect(GatewayActivity.summarize([]) == GatewayActivity())
    }

    @Test func newestFirstFiltersByProject() {
        let entries = [entry("a", at: 1), entry("b", at: 2), entry("a", at: 3)]
        #expect(entries.newestFirst(project: "a").map(\.date.timeIntervalSince1970) == [3, 1])
        #expect(entries.newestFirst().count == 3)
    }
}

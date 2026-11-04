import Foundation
import Testing
@testable import PaddockCore

private func events(_ name: String) throws -> [SbxEvent] {
    try SandboxdFixture.lines(name).compactMap { try SbxEventDecoder.decode(line: $0) }
}

/// Entries in one order, since the log's order is sbx's and the events' order is theirs.
private func sorted(_ log: SbxPolicyLog) -> [[SbxPolicyLog.Entry]] {
    let key = { (entry: SbxPolicyLog.Entry) in [entry.sandboxId, entry.host, entry.proxyType ?? "", entry.rule ?? ""] }
    return [log.allowed, log.blocked].map { $0.sorted { key($0).lexicographicallyPrecedes(key($1)) } }
}

private func log(from events: [SbxEvent]) -> SbxPolicyLog {
    var log = SbxPolicyLog(allowed: [], blocked: [])
    for event in events { log.apply(event) }
    return log
}

@Suite("Network log from events")
struct NetworkLogEventsTests {
    @Test func theReplayIsTheLog() async throws {
        let all = try events("events.ndjson")
        let replay = Array(all.prefix { !$0.isSyncComplete })
        let expected = try Fixture.decode(SbxPolicyLog.self, "sandboxd", "cli-policy-log.json")
        #expect(sorted(log(from: replay)) == sorted(expected))
        #expect(log(from: replay).activity == expected.activity)
    }

    /// The live events after the replay, up to the moment sbx read the log again, give that log.
    @Test func liveEventsKeepItCurrent() async throws {
        let transport = FakeSandboxdTransport()
        transport.respond(to: "/policy/network/log", with: try Fixture.data("sandboxd", "policy-network-log-later.json"))
        let expected = try await SandboxdReads(transport: transport).policyLog(sandbox: nil)
        let built = log(from: try events("events.ndjson"))
        #expect(sorted(built) == sorted(expected))
        #expect(built != log(from: Array(try events("events.ndjson").prefix { !$0.isSyncComplete })))
    }

    @Test func aKnownHostIsUpdatedANewOneAdded() async throws {
        let all = try events("events.ndjson") + events("events-more.ndjson")
        let syncAt = try #require(all.firstIndex { $0.isSyncComplete })
        var log = log(from: Array(all[..<syncAt]))
        var changes: [SbxPolicyLog.Change] = []
        for event in all[syncAt...] where event.kind == .policyNetwork { changes.append(log.apply(event)) }
        #expect(changes.contains(.updated))
        #expect(changes.contains { if case .added = $0 { true } else { false } })
        #expect(!changes.contains(.none))
    }

    @Test func otherEventsChangeNothing() async throws {
        var log = SbxPolicyLog(allowed: [], blocked: [])
        for event in try events("events.ndjson") where event.kind != .policyNetwork {
            #expect(log.apply(event) == .none)
        }
        #expect(log == SbxPolicyLog(allowed: [], blocked: []))
    }
}

@Suite("ActivityTimeline")
struct ActivityTimelineTests {
    /// What the app does: the replay builds the log, only what follows is recorded.
    private func timeline(_ events: [SbxEvent]) -> ActivityTimeline {
        var log = SbxPolicyLog(allowed: [], blocked: [])
        var timeline = ActivityTimeline()
        var synced = false
        for event in events {
            let change = log.apply(event)
            if synced { timeline.record(event, change: change) }
            if event.isSyncComplete { synced = true }
        }
        return timeline
    }

    @Test func aNewSandboxFromTheCapture() async throws {
        let all = try events("events.ndjson") + events("events-more.ndjson")
        let timeline = timeline(all)
        let created = try #require(all.first { $0.action == "created" }?.sandboxName)
        let kinds = timeline[created].map(\.kind)
        #expect(kinds.contains(.lifecycle("created")))
        #expect(kinds.contains(.lifecycle("started")))
        #expect(kinds.contains { if case .connected = $0 { true } else { false } })
        // newest first
        let dates = timeline[created].map(\.date)
        #expect(dates == dates.sorted(by: >))
    }

    @Test func onlyNewHostsAreNews() async throws {
        let all = try events("events.ndjson") + events("events-more.ndjson")
        let syncAt = try #require(all.firstIndex { $0.isSyncComplete })
        let live = all[(syncAt + 1)...].filter { $0.kind == .policyNetwork }
        let recorded = timeline(all).entries.values.flatMap { $0 }.filter {
            if case .lifecycle = $0.kind { false } else if case .ports = $0.kind { false } else { true }
        }
        #expect(recorded.count < live.count)
        #expect(!recorded.isEmpty)
    }

    @Test func theReplayIsNotRecorded() async throws {
        let all = try events("events.ndjson")
        let replay = Array(all.prefix { !$0.isSyncComplete })
        #expect(timeline(replay + [all[replay.count]]).entries.isEmpty)
    }

    @Test func keepsTheNewestAndForgetsARemovedSandbox() async throws {
        var timeline = ActivityTimeline()
        func lifecycle(_ action: String, _ n: Int) -> SbxEvent {
            SbxEvent(id: "e\(n)", type: "sandbox.lifecycle", action: action, timestamp: Date(timeIntervalSince1970: Double(n)),
                     sandboxName: "a", sandboxId: nil, createdAt: nil, data: nil)
        }
        for n in 0..<(ActivityTimeline.limit + 5) { timeline.record(lifecycle(n.isMultiple(of: 2) ? "started" : "stopped", n)) }
        #expect(timeline["a"].count == ActivityTimeline.limit)
        #expect(timeline["a"].first?.id == "e\(ActivityTimeline.limit + 4)")
        timeline.record(lifecycle("deleted", 999))
        #expect(timeline["a"].isEmpty)
    }

    @Test func publishedPortsAreCounted() async throws {
        let all = try events("events.ndjson")
        let ports = try #require(all.first { $0.kind == .sandboxPorts })
        var timeline = ActivityTimeline()
        timeline.record(ports)
        #expect(timeline[ports.sandboxName ?? ""].map(\.kind) == [.ports(0)])
    }

    /// What the app puts in the Log (PAD-59): the entry it recorded, and nothing for what it did not.
    @Test func recordReturnsTheEntryForTheLog() async throws {
        var timeline = ActivityTimeline()
        let started = SbxEvent(id: "e1", type: "sandbox.lifecycle", action: "started",
                               timestamp: Date(timeIntervalSince1970: 1),
                               sandboxName: "a", sandboxId: nil, createdAt: nil, data: nil)
        #expect(timeline.record(started)?.logLine == "Started")
        let sync = SbxEvent(id: "e2", type: "sync", action: "complete", timestamp: Date(timeIntervalSince1970: 2),
                            sandboxName: "a", sandboxId: nil, createdAt: nil, data: nil)
        #expect(timeline.record(sync) == nil)
        let blocked = ActivityTimeline.Entry(id: "e3", date: Date(), sandbox: "a",
                                             kind: .blocked(host: "evil.example:443", reason: "denied by rule"))
        #expect(blocked.text == "Blocked from evil.example:443")
        #expect(blocked.logLine == "Blocked from evil.example:443: denied by rule")
    }
}

@Suite("Approval updates")
struct ApprovalUpdatesTests {
    let sbx = URL(fileURLWithPath: "/sbx")

    /// The first list a stream yields, then the stream is cancelled.
    private func first(_ stream: AsyncThrowingStream<[SbxApproval], any Error>) async throws -> [SbxApproval]? {
        let reader = Task { () -> [SbxApproval]? in
            for try await list in stream { return list }
            return nil
        }
        defer { reader.cancel() }
        return try await reader.value
    }

    @Test func fromTheSocketAfterItsReplay() async throws {
        let transport = try SandboxdFixture.transport()
        transport.hold("/user-prompts")
        let expected = try Fixture.decode([SbxApproval].self, "sandboxd", "cli-policy-approval-ls.json")
        #expect(try await first(SandboxdReads(transport: transport).approvalUpdates()) == expected)
    }

    /// Each line after the replay reads the list again.
    @Test func aNewRequestReadsTheListAgain() async throws {
        let transport = try SandboxdFixture.transport()
        let lines = try SandboxdFixture.lines("user-prompts.ndjson")
        let request = try #require(lines.first)
        transport.stream("/user-prompts", lines: lines + [request])
        transport.hold("/user-prompts")
        let stream = SandboxdReads(transport: transport).approvalUpdates()
        let reader = Task {
            var count = 0
            for try await _ in stream {
                count += 1
                if count == 2 { return count }
            }
            return count
        }
        #expect(try await reader.value == 2)
        // the live stream, then one full read per change
        #expect(transport.requests.filter { $0 == "/user-prompts" }.count >= 3)
    }

    @Test func theCLIPolls() async throws {
        let runner = try SandboxdFixture.runner()
        let reads = SbxCLIReads(runner: runner, sbx: sbx)
        let expected = try Fixture.decode([SbxApproval].self, "sandboxd", "cli-policy-approval-ls.json")
        #expect(try await first(reads.approvalUpdates()) == expected)
        #expect(runner.calls == [["policy", "approval", "ls", "--json"]])
    }

    @Test func fallsBackToPollingWhenTheSocketStreamFails() async throws {
        let transport = try SandboxdFixture.transport()
        transport.fail("/user-prompts", with: .unreachable(path: "/user-prompts", message: "refused"))
        let runner = try SandboxdFixture.runner()
        let reads = FallbackSbxReads(cli: SbxCLIReads(runner: runner, sbx: sbx)) {
            .init(reads: SandboxdReads(transport: transport), apiVersion: "0.42.0")
        }
        #expect(try await first(reads.approvalUpdates())?.count == 2)
        #expect(runner.calls == [["policy", "approval", "ls", "--json"]])
    }

    @Test func anUnknownAPIIsReportedAsSuch() async throws {
        let reads = FallbackSbxReads(cli: SbxCLIReads(runner: try SandboxdFixture.runner(), sbx: sbx)) {
            throw SandboxdError.unsupportedAPI(found: "0.43.0")
        }
        _ = try await reads.sandboxes()
        #expect(await reads.source == .unsupportedAPI(found: "0.43.0"))
    }
}

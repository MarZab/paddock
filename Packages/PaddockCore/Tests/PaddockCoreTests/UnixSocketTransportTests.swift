import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import Testing
@testable import PaddockCore

/// A fake sandboxd on a real Unix socket, in a folder with a space in its name like sbx's
/// `Application Support`: answers from the fixtures, NDJSON streamed in chunks.
final class FakeSandboxdServer: Sendable {
    let channel: NIOAsyncChannel<NIOAsyncChannel<HTTPServerRequestPart, HTTPServerResponsePart>, Never>
    let socketPath: String
    let directory: String

    init() async throws {
        directory = NSTemporaryDirectory() + "Paddock Test \(UUID().uuidString.prefix(8))"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        socketPath = directory + "/sandboxd.sock"
        channel = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .bind(unixDomainSocketPath: socketPath) { child in
                child.eventLoop.makeCompletedFuture {
                    try child.pipeline.syncOperations.configureHTTPServerPipeline()
                    return try NIOAsyncChannel<HTTPServerRequestPart, HTTPServerResponsePart>(wrappingChannelSynchronously: child)
                }
            }
    }

    func serve() async throws {
        try await withThrowingDiscardingTaskGroup { group in
            try await channel.executeThenClose { inbound in
                for try await connection in inbound {
                    group.addTask {
                        try? await connection.executeThenClose { requests, out in
                            for try await part in requests {
                                if case .head(let head) = part {
                                    // Like sandboxd (Go's HTTP server): HTTP/1.1 needs a Host header.
                                    try await head.headers["host"].isEmpty ? Self.badRequest(out) : Self.reply(head.uri, out)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func stop() async {
        try? await channel.channel.close()
        try? FileManager.default.removeItem(atPath: directory)
    }

    static func badRequest(_ out: NIOAsyncChannelOutboundWriter<HTTPServerResponsePart>) async throws {
        let body = ByteBuffer(string: "400 Bad Request: missing required Host header")
        var headers = HTTPHeaders()
        headers.add(name: "content-length", value: "\(body.readableBytes)")
        try await out.write(.head(HTTPResponseHead(version: .http1_1, status: .badRequest, headers: headers)))
        try await out.write(.body(.byteBuffer(body)))
        try await out.write(.end(nil))
    }

    static func reply(_ path: String, _ out: NIOAsyncChannelOutboundWriter<HTTPServerResponsePart>) async throws {
        var headers = HTTPHeaders()
        switch path {
        case "/daemon/health":
            let body = ByteBuffer(bytes: try Fixture.data("sandboxd", "daemon-health.json"))
            headers.add(name: "content-type", value: "application/json")
            headers.add(name: "content-length", value: "\(body.readableBytes)")
            try await out.write(.head(HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)))
            try await out.write(.body(.byteBuffer(body)))
        case "/events", "/user-prompts":
            let name = path == "/events" ? "events.ndjson" : "user-prompts.ndjson"
            headers.add(name: "content-type", value: "application/x-ndjson")
            headers.add(name: "transfer-encoding", value: "chunked")
            try await out.write(.head(HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)))
            // Lines split across chunks, as a stream may deliver them.
            let text = String(decoding: try Fixture.data("sandboxd", name), as: UTF8.self)
            for piece in stride(from: 0, to: text.utf8.count, by: 700) {
                let bytes = Array(text.utf8.dropFirst(piece).prefix(700))
                try await out.write(.body(.byteBuffer(ByteBuffer(bytes: bytes))))
            }
        default:
            let body = ByteBuffer(string: #"{"message":"not found"}"#)
            headers.add(name: "content-length", value: "\(body.readableBytes)")
            try await out.write(.head(HTTPResponseHead(version: .http1_1, status: .notFound, headers: headers)))
            try await out.write(.body(.byteBuffer(body)))
        }
        try await out.write(.end(nil))
    }
}

/// The transport the app uses, against a real socket (the fakes elsewhere skip it).
@Suite("UnixSocketTransport")
struct UnixSocketTransportTests {
    private func withServer(_ body: (SandboxdReads, FakeSandboxdServer) async throws -> Void) async throws {
        let server = try await FakeSandboxdServer()
        let serving = Task { try await server.serve() }
        defer { serving.cancel() }
        try await body(SandboxdReads(transport: UnixSocketTransport(socketPath: server.socketPath)), server)
        await server.stop()
    }

    @Test func healthOverTheSocket() async throws {
        try await withServer { reads, server in
            #expect(server.socketPath.contains(" "))
            let health = try await reads.checkHealth()
            #expect(health.apiVersion == "0.42.0")
        }
    }

    @Test func eventsStreamOverTheSocket() async throws {
        try await withServer { reads, _ in
            var events: [SbxEvent] = []
            for try await event in reads.events() { events.append(event) }
            let expected = try SandboxdFixture.lines("events.ndjson").compactMap { try SbxEventDecoder.decode(line: $0) }
            #expect(events == expected)
        }
    }

    @Test func approvalsReadUpToSynced() async throws {
        try await withServer { reads, _ in
            let approvals = try await reads.approvals()
            #expect(approvals == (try Fixture.decode([SbxApproval].self, "sandboxd", "cli-policy-approval-ls.json")))
        }
    }

    @Test func anErrorStatusIsReported() async throws {
        try await withServer { reads, _ in
            await #expect(throws: SandboxdError.status(path: "/sandbox", code: 404, body: #"{"message":"not found"}"#)) {
                try await reads.sandboxes()
            }
        }
    }

    /// At once, not after the timeout, so the CLI answers instead.
    @Test func aMissingSocketIsUnreachable() async throws {
        let reads = SandboxdReads(transport: UnixSocketTransport(socketPath: NSTemporaryDirectory() + "no-such-\(UUID()).sock"))
        let started = ContinuousClock.now
        do {
            _ = try await reads.checkHealth()
            Issue.record("a missing socket answered")
        } catch let error as SandboxdError {
            guard case .unreachable(_, let message) = error else { Issue.record("expected unreachable, got \(error)"); return }
            // The connect failed, not the request's deadline: a time limit alone fails on a loaded CI
            // runner, where this took 5 s with nothing waiting.
            #expect(message.contains("No such file or directory"))
        }
        #expect(ContinuousClock.now - started < .seconds(15))
    }

    /// A stream has no deadline, so a socket that is gone must fail it rather than hang.
    @Test func aStreamOnAMissingSocketFails() async throws {
        let reads = SandboxdReads(transport: UnixSocketTransport(socketPath: NSTemporaryDirectory() + "no-such-\(UUID()).sock"))
        let started = ContinuousClock.now
        let error = await #expect(throws: SandboxdError.self) {
            for try await _ in reads.events() {}
        }
        #expect(error.map { "\($0)".contains("No such file or directory") } ?? false)
        // Hanging would be for ever; the limit only has to be well short of that (PAD-112).
        #expect(ContinuousClock.now - started < .seconds(15))
    }

    /// sandboxd went away (stopped, restarted) while a stream was open: the stream ends.
    @Test func aStreamEndsWhenSandboxdStops() async throws {
        let server = try await FakeSandboxdServer()
        let serving = Task { try await server.serve() }
        let reads = SandboxdReads(transport: UnixSocketTransport(socketPath: server.socketPath))
        let health = try await reads.checkHealth()
        #expect(health.status == "healthy")
        serving.cancel()
        await server.stop()
        let started = ContinuousClock.now
        await #expect(throws: (any Error).self) { _ = try await reads.checkHealth() }
        #expect(ContinuousClock.now - started < .seconds(UnixSocketTransport.timeout.nanoseconds / 1_000_000_000))
    }
}

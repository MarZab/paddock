---
id: doc-2
title: ProcessRunner
type: specification
created_date: '2026-10-25 15:55'
updated_date: '2026-10-28 21:13'
---
- `run(_ cmd:, args:, env:) async throws -> ProcessResult` returns stdout, stderr, and exit code.
- **Waiting holds no shared thread.** Each pipe is read, and stdin written, on a plain `Thread` of its own; the exit arrives through `Process.terminationHandler`; the caller waits on a continuation. Never block inside `Task.detached` (it runs on the same cooperative pool as every actor) or on a GCD global queue (its workers are capped): a handful of stuck commands used to stall the whole app (PAD-28). `readabilityHandler` is not used either, since it misses EOFs on Linux.
- **Cancellation:** cancelling the caller throws `CancellationError` at once and terminates the process, even if its exit is never noticed; a cancel before launch starts nothing.
- `stream(...) -> AsyncThrowingStream<String, Error>` emits one element per line, for NDJSON and logs. Every streamed process is tracked so the app can end them all when it quits (`FoundationLineStreamer.terminateAll`).
- **Signals:** both start processes with `Process.runUnmasked()`, so a child does not inherit the blocked signal mask of Swift's worker threads and `terminate()` reaches it (PAD-30; backlog doc Kits, Watchers).
- **Binary lookup:** `/opt/homebrew/bin`, `/usr/local/bin`, plus the login-shell PATH (`/bin/zsh -lc 'echo $PATH'`), resolved once at launch.
- Defined as a protocol, so tests can inject a fake that returns fixtures.

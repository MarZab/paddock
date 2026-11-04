import Foundation

/// Waiting with a time limit for work that cannot be interrupted (an sbx process). A task group
/// would wait for its child to finish even after cancelling it, so this races the work against a
/// timer instead: whichever finishes first wins, and a stuck call goes on in the background with
/// its result dropped.
enum Deadline {
    struct Expired: Error, CustomStringConvertible {
        let duration: Duration
        var description: String { "no answer within \(duration)" }
    }

    static func result<T: Sendable>(within duration: Duration, of work: @escaping @Sendable () async throws -> T) async throws -> T {
        let once = Once()
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                do {
                    let value = try await work()
                    if once.claim() { continuation.resume(returning: value) }
                } catch {
                    if once.claim() { continuation.resume(throwing: error) }
                }
            }
            Task {
                try? await Task.sleep(for: duration)
                if once.claim() { continuation.resume(throwing: Expired(duration: duration)) }
            }
        }
    }

    /// True for the first caller only.
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed = false

        func claim() -> Bool {
            lock.withLock {
                defer { claimed = true }
                return !claimed
            }
        }
    }
}

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

extension Process {
    /// Starts the process with its signals unblocked, as the terminals' `pty.c` does. A child
    /// inherits the signal mask of the thread that starts it, and Swift's worker threads block
    /// nearly every signal (Linux's libdispatch does; Foundation there passes the mask on). A child
    /// started from one ignored `terminate()`: SIGTERM stayed pending (PAD-30). The mask is cleared
    /// on this thread only while the child starts.
    ///
    /// On macOS Foundation follows exits through kqueue, so the whole mask is cleared. On Linux,
    /// where only the tests run, Foundation follows them through SIGCHLD, which a quick child could
    /// deliver to this thread meanwhile and so get lost; SIGCHLD stays blocked there, and a shell
    /// that waits for its own children needs it unblocked by whoever starts it (the tests do).
    func runUnmasked() throws {
        var mask = sigset_t()
        var previous = sigset_t()
        sigemptyset(&mask)
        #if !canImport(Darwin)
        sigaddset(&mask, SIGCHLD)
        #endif
        pthread_sigmask(SIG_SETMASK, &mask, &previous)
        defer { pthread_sigmask(SIG_SETMASK, &previous, nil) }
        try run()
    }
}

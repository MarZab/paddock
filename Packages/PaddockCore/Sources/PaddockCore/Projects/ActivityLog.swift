import Foundation

/// Where long work writes what it does, line by line, for the Log window (and its file on disk).
/// Lines are operator-visible output (an image build's steps and docker's own output), never
/// secrets, request bodies, or headers.
public typealias LogSink = @Sendable (String) -> Void

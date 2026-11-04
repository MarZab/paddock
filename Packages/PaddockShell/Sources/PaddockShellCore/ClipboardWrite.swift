import Foundation

/// What a program in a terminal asks to copy (OSC 52), such as Claude Code copying what was
/// selected in its own view while it tracks the mouse (PAD-66).
///
/// The program runs in the sandbox, so it never sets the Mac's clipboard itself: the terminal keeps
/// the text, and the right-click menu's Copy puts it on the clipboard when the operator chooses it.
/// Only UTF-8 text up to `maxBytes` is kept. Reading the clipboard (an OSC 52 query) is never allowed.
public enum ClipboardWrite {
    /// The most a write may hold.
    public static let maxBytes = 1 << 20

    /// The text to keep for the menu, or nil when the write is refused.
    public static func text(_ content: Data) -> String? {
        guard !content.isEmpty, content.count <= maxBytes,
              let text = String(data: content, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
}

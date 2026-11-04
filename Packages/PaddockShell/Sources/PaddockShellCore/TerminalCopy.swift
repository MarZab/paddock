import Foundation

/// What a terminal's Copy takes, and when Ctrl-C copies instead of interrupting (PAD-79; backlog
/// doc PaddockShell).
public enum TerminalCopy {
    /// The right-click Copy: the terminal's own selection (live, or kept after output cleared it),
    /// else what the program last copied (OSC 52). Empty text counts as nothing.
    public static func text(selection: String?, programCopy: String?) -> String? {
        if let selection, !selection.isEmpty { return selection }
        if let programCopy, !programCopy.isEmpty { return programCopy }
        return nil
    }

    /// Whether a key press is Ctrl-C alone: Control and the C key, without Command, Option, or
    /// Shift (Ctrl-Shift-C and the rest go to the program untouched).
    public static func isControlC(key: String?, control: Bool, command: Bool, option: Bool, shift: Bool) -> Bool {
        control && !command && !option && !shift && key?.lowercased() == "c"
    }

    /// What Ctrl-C does: copy `text` when there is something to copy, else send the interrupt.
    /// After a copy the caller drops the selection and the program's copy, so a second Ctrl-C
    /// interrupts: the key still stops an agent.
    public static func controlC(selection: String?, programCopy: String?) -> ControlC {
        text(selection: selection, programCopy: programCopy).map(ControlC.copy) ?? .interrupt
    }

    public enum ControlC: Equatable, Sendable {
        case copy(String)
        case interrupt
    }
}

import PaddockShellCore
import Testing

@Suite("TerminalCopy")
struct TerminalCopyTests {
    @Test func copyTakesTheSelectionElseWhatTheProgramCopied() {
        #expect(TerminalCopy.text(selection: "mine", programCopy: "claude's") == "mine")
        #expect(TerminalCopy.text(selection: nil, programCopy: "claude's") == "claude's")
        #expect(TerminalCopy.text(selection: "", programCopy: "") == nil)
        #expect(TerminalCopy.text(selection: nil, programCopy: nil) == nil)
    }

    @Test func controlCCopiesWhenThereIsSomethingElseInterrupts() {
        #expect(TerminalCopy.controlC(selection: "mine", programCopy: nil) == .copy("mine"))
        #expect(TerminalCopy.controlC(selection: nil, programCopy: "claude's") == .copy("claude's"))
        // nothing to copy (or the copy was spent): the program gets its interrupt
        #expect(TerminalCopy.controlC(selection: nil, programCopy: nil) == .interrupt)
    }

    @Test(arguments: [
        ("c", true, false, false, false, true),
        ("C", true, false, false, false, true),
        ("c", true, false, false, true, false),   // Ctrl-Shift-C goes to the program
        ("c", true, true, false, false, false),   // Cmd-Ctrl-C
        ("c", true, false, true, false, false),   // Ctrl-Option-C
        ("c", false, true, false, false, false),  // Cmd-C is the Edit menu's Copy
        ("d", true, false, false, false, false),
        (nil, true, false, false, false, false),
    ] as [(String?, Bool, Bool, Bool, Bool, Bool)])
    func onlyPlainControlCCounts(key: String?, control: Bool, command: Bool, option: Bool, shift: Bool, expected: Bool) {
        #expect(TerminalCopy.isControlC(key: key, control: control, command: command, option: option, shift: shift) == expected)
    }
}

# Changelog

One line per change, newest first, grouped by the day of the version (yymmdd, as in the app's yymmdd.N). Details are in the ticket (`backlog task view PAD-N`).

## Unreleased

- PAD-145 Projects can be put in groups in Info, and each group folds from its title in the sidebar.
- PAD-144 There is no New Window: Paddock is one window.
- PAD-143 The Playwright tab keeps its page when another tab shows, and no longer disappears on its own.
- PAD-142 The browser kit's Playwright MCP browser keeps its logins and loads Chromium extensions.
- PAD-141 Claude Code in a sandbox with the browser kit gets Playwright MCP, and its pages show in the Playwright tab.
- PAD-139 Publishing a port can set the port on the Mac too.
- PAD-137 A project with its own .azure, .ssh or Library folder can be created after a confirmation.
- PAD-136 An extra folder can be made writable again; it no longer reports a false ~/Library/Logs error.

## 261107

- PAD-134 A create no longer reports an error because sbx lists its own sbx-kit-builder sandbox.
- PAD-133 After a recreate, the Claude sessions and sbxenv.yaml items no longer stay.
- PAD-132 A project's title bar has Recreate whenever there is a sandbox.
- PAD-131 A project's Info is a page of cards that wrap with the window.
- PAD-130 Claude's sessions can be kept on this Mac for projects with an sbxenv.yaml too.
- PAD-127 Claude's sessions can be kept on this Mac across recreates, and cleared in Info.
- PAD-125 An extra folder may be inside ~/Library/Logs, always read-only, with a warning.
- PAD-124 Extra folders take a pasted or typed path, checked as you type, or a dropped folder.
- PAD-123 Network counts Paddock's suggestions, and the rules table sorts by any column.
- PAD-122 The sidebar's Log shows a red dot when an error arrived since it was last opened.
- PAD-121 Paddock captures diagnostics of itself when it hangs, or on demand (System menu).
- PAD-120 The microphone follows the tab in front; another tab no longer holds it.
- PAD-119 Verbose Log (System menu) says what became of each voice message.
- PAD-118 The speech model download shows its progress and starts listening when done.

## 261106

- PAD-33 Project cards and the toolbar name waiting approval requests in their tooltip.
- PAD-104 The version (yymmdd.N, from git) shows next to the status button.
- PAD-103 Recreate items say what changed, and are gone when nothing did.
- PAD-100 Reads go through sandboxd's socket again with sbx 0.51 (API 0.49).
- PAD-101 A closed voice popup keeps its agent silent; a say no longer opens it.
- PAD-97 The log stays quiet while the Mac sleeps; repeated read errors are logged once.

---
id: doc-13
title: ProjectStore
type: specification
created_date: '2026-10-25 15:55'
updated_date: '2026-11-06 07:46'
---
One hand-editable file per project, `~/.config/paddock/projects/<sandbox-name>.json`, next to `paddock.yaml`. It holds only the operator's decisions sbx cannot store; ports and rules live in sbx (see Where state lives):

```json
{
  "version": 1,
  "id": "6F1C2D3E-4A5B-4C6D-8E7F-0123456789AB",
  "name": "paddock-app",
  "folder": "/Users/operator/Projects/app",
  "agent": "claude",
  "provider": "local_qwen",
  "cloneMode": false,
  "gatewayPort": 17480,
  "approvedEnvironment": "3f1c...e9",
  "declinedHosts": ["ads.example.com"],
  "sandboxEnvironment": "3f1c...e9"
}
```

- `agent` and `provider` name sections of `paddock.yaml`, chosen in the New Project sheet. A project's `sbxenv.yaml` only pre-fills the name and agent there, so the agent cannot switch its own provider.
- `approvedEnvironment` (optional): the fingerprint of the `sbxenv.yaml` (and its own kits) the operator confirmed; `declinedHosts` the runtime hosts they declined then; `sandboxEnvironment` the fingerprint the sandbox was created from, and `sandboxEnvironmentRecord` the same piece by piece (each `sbxenv.yaml` key and project-kit file by hash), so Sync can say what changed (PAD-103). A differing pair is a recreate item in Sync (backlog doc Project config file). Keys from before (`approvedConfigHash`, `imageTag`, `ports`, `network`, `policy`) are ignored.
- `gatewayPort` is assigned once, from `models.gatewayPorts`, when the project uses a local model.
- `extraFolders` (optional, PAD-73.5): `[{"path", "readOnly"}]`, folders mounted besides the project folder in the order added. `readOnly` defaults to true, and the paths are canonical as checked when added. Only the operator adds them, in Paddock.
- `terminalTheme` (optional) is the `TerminalTheme` id the operator picked in Info for the project's terminals; left out, they keep the terminal's own colors. It is never read from the project folder.
- Files are written atomically and owner-only. A bad file (malformed, newer version, a name that does not match the file name, or a name, folder, or gateway port another project already uses) is shown as a problem and skipped; the other projects still load.
- `ProjectDirectory` loads and saves them; `ProjectList` holds the rules that span projects; `NewProject` turns the sheet's draft into a project (FolderPolicy, unique name and folder, no existing sbx sandbox of that name, defined sections, and extra folders that pass `ExtraFolders`). Its `sbxenv.yaml` is confirmed later, before the first create.
- All Paddock files live in this one folder. Paddock stores no secrets.

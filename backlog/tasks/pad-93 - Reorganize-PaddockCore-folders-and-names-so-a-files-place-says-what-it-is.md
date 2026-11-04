---
id: PAD-93
title: Reorganize PaddockCore folders and names so a file's place says what it is
status: To Do
assignee: []
created_date: '2026-11-04 18:43'
updated_date: '2026-11-04 18:54'
labels:
  - architecture
  - naming
dependencies: []
priority: low
type: chore
ordinal: 98000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Review 2026-11-04. Agents/ (20 files) mixes agent launching (AgentLaunch, ClaudeGateway), kit generators (AgentStatusKit, VoiceKit, BrowserKit, NodeKit), the browser feature (BrowserShow/Activity/Capture/WebPolicy), Markdown rendering (MarkdownPage, MarkdownRenderer, MarkdownPageStyle), web view policies (NativeShowPolicy, OpenUIPolicy) and sidebar state (SidebarAgents, AgentTabMarks). Projects/ (14) mixes the project model and store with Ports/PortsTable/RulesTable/HostRules/SandboxTop/ActivityLog/ExternalShell. Kit code is spread over Config/Kits.swift, Agents/KitFile.swift, Environment/ProjectKitFile.swift and SbxKitDescriptor. Names: 'Environment' (sbxenv) vs 'Config' (paddock.yaml) vs 'Setup'; Sbx* prefix inconsistent (HostPattern, PolicyPlanner under Sbx/; HostRules, RulesTable under Projects/). Voice (12 files) sits in the core target next to the gateway. Tests are 43 flat files and Fixtures has 66 files in ten folders listed one by one in Package.swift.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A proposal doc (backlog doc) with the target layout: Kits/, Browser/, Markdown/, WebPolicy/, Ports/, Network/ (rules, host patterns, planner), Projects/ (model and store only), each file mapped; operator approves it before moving files
- [ ] #2 Files moved with git mv in one mechanical commit with no code change; tests mirror the source folders
- [ ] #3 Evaluate splitting targets (PaddockGateway as its own library with NIO and AsyncHTTPClient, PaddockVoice) so the core does not pull SwiftNIO and Markdown into every consumer; record the decision
- [ ] #4 Package.swift copies Fixtures as one resource folder, not ten entries
- [ ] #5 Code comments and docs that name files are updated
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Not started in the 2026-11-04 fix pass: no Swift toolchain in that sandbox, and this change is too large to make uncompiled.
<!-- SECTION:NOTES:END -->

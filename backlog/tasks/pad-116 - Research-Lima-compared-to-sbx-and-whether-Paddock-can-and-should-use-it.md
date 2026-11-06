---
id: PAD-116
title: 'Research: Lima compared to sbx, and whether Paddock can and should use it'
status: To Do
assignee: []
created_date: '2026-11-06 09:14'
labels:
  - research
dependencies: []
ordinal: 121000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Paddock is built on Docker Sandboxes (sbx): one microVM per project folder, with sbx owning the network rules, secrets, kits, and llmman. Lima (lima-vm.io) is another way to run Linux VMs on a Mac, with its own mounts, networking, templates, and a growing set of sandbox/agent use cases. Before the app depends further on sbx, we want a written answer on how Lima compares, whether Paddock could use it (as a replacement or a second backend), and whether it should.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A comparison of Lima and sbx is written as a backlog doc: isolation model, mounts and folder policy, network control (can Paddock enforce rules like sbx global rules, per-sandbox denies, and a loopback-only gateway), secrets and credential handling, agent and kit support, model access (llmman equivalent), lifecycle and CLI/API (JSON output, events), Apple Silicon performance, licensing, maintenance, and install story
- [ ] #2 Each Paddock security rule (CLAUDE.md, Security rules) is checked against Lima: which ones Lima could meet, which need new Paddock code, and which cannot be met
- [ ] #3 The doc says what supporting Lima would cost in PaddockCore (SbxService, SbxReads, network policy, kits, ProcessRunner fixtures) and whether it could sit behind a protocol as a second backend
- [ ] #4 Any claim about Lima behavior is verified by running limactl on the Mac or from Lima docs with a link, not guessed; captured output is saved as fixtures if a prototype is tried
- [ ] #5 The doc ends with a recommendation (adopt, support as a second backend, or do not use) with reasons, and follow-up tickets are created for anything it recommends
<!-- AC:END -->

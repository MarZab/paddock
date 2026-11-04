---
id: PAD-76
title: paddock.toml becomes paddock.yaml; drop TOML
status: Done
assignee: []
created_date: '2026-11-04 10:06'
updated_date: '2026-11-04 15:07'
labels: []
dependencies:
  - PAD-73.3
documentation:
  - doc-10
priority: medium
type: enhancement
ordinal: 81000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Projects describe their sandbox in sbx's `sbxenv.yaml` and v3 kits (PAD-73), both YAML. The operator asked (2026-11-04) for Paddock's own config to be YAML too, for consistency. Once `.paddock.toml` is gone (PAD-73.3), `paddock.toml` is the only TOML left.

Today TOMLCoding turns TOML into JSON before decoding, so AppConfig's typed model and unknown-key checks do not depend on the format. "Add kit" (`AppConfigFile.addKit`) appends text and keeps the operator's comments, and the YAML version has to do the same.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 AppConfig loads `~/.config/paddock/paddock.yaml` (or the XDG override) with the same typed model, defaults, and unknown-key reports; fixture tests are converted
- [x] #2 Adding a kit from the interface inserts `NAME:` under `kits:` in paddock.yaml, keeping every comment and other key (tests for a file with and without `kits:`, and with comments)
- [x] #3 The template written by Edit Config is YAML with the same commented-out sections
- [x] #4 TOMLKit is removed from Package.swift; backlog docs App config, Kits, and Overview, CLAUDE.md, and README name paddock.yaml
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Done except TOMLKit removal, which waits for PAD-73.3 to drop .paddock.toml (the dependency). AppConfig reads paddock.yaml (YAMLCoding; null sections absent, keyless kits empty, unknown empty sections still reported) or, alone, paddock.toml; PaddockPaths.activeAppConfig picks. AppConfigFile.insertingKit adds under kits: without touching other lines; convertLegacy writes paddock.yaml from paddock.toml only when both read to the same config and unknown keys, never touching the TOML file. App: reloadConfig/addKit/editAppConfig use the active file, a deprecation line in configProblems, File > Convert to paddock.yaml with an NSAlert confirmation (not compiled here; build on the Mac). Fixtures converted to YAML (TOML twins kept and tested equal). Docs: App config, Kits, Overview, ProjectStore, Security rules, UI, ModelGateway; CLAUDE.md.

Operator (2026-11-04): no legacy converters. Removed paddock.toml reading, PaddockPaths.legacyAppConfig/activeAppConfig, AppConfigFile.convertLegacy, the File menu action, and the TOML fixtures. paddock.yaml is the only app config. TOMLKit remains only for .paddock.toml until PAD-73.3.

TOMLKit removed from Package.swift and Package.resolved; TOMLCoding gone. README names no config file, so nothing to change there; CLAUDE.md, Overview, App config, and Kits name paddock.yaml.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Paddock's config is paddock.yaml (YAML 1.2 core schema through Yams, the same typed model and unknown-key reports), Add Kit inserts into it keeping comments, and the Edit Config template is YAML. With .paddock.toml gone, TOML and TOMLKit are removed entirely.
<!-- SECTION:FINAL_SUMMARY:END -->

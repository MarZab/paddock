---
id: PAD-74
title: 'New projects are named after their folder, without a paddock- prefix'
status: Done
assignee: []
created_date: '2026-11-04 09:47'
updated_date: '2026-11-04 09:49'
labels: []
dependencies: []
priority: medium
type: enhancement
ordinal: 79000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Paddock suggests `paddock-<folder>` as a new project's sandbox name. A project set up for plain sbx (an `sbxenv.yaml` and `mr claude`, PAD-73) names its sandbox after the folder, so the same folder ended up under two names, and the prefix adds nothing in `sbx ls`. The operator asked (2026-11-04) to stop prefixing. Existing projects keep their names, since renaming a sandbox means recreating it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A new project's suggested name is the folder name, lowercased and reduced to sbx's characters, with no `paddock-` prefix
- [x] #2 A folder whose cleaned name is not a valid sbx name (empty, one character, or `default`) gets a valid suggestion; taken names still get `-2`, `-3`
- [x] #3 The `paddock-` special case is gone from name validation and from the gateway trial's error message
- [x] #4 Tests cover the new suggestions; backlog doc App config describes the naming
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
NewProject.suggestedName now suggests the folder name itself (`/src/My App` -> `my-app`), falling back to `project` or `project-<name>` when sbx would refuse the bare name (empty, one character, `default`). ProjectList.sandboxPrefix and the `paddock-` special case in NewProject.make are gone; the gateway trial says "not a valid sbx sandbox name". Existing projects keep their names. Tests: ProjectsTests suggestions (incl. `x` and `Default`), uniqueness, and validation; full `swift test` on Linux passes (545 tests). Doc App config updated. Follow-up to consider: a folder that already has a sandbox of the same name made outside Paddock (`sbx env run`) gets `<name>-2` in the New Project sheet instead of adopting that sandbox.
<!-- SECTION:FINAL_SUMMARY:END -->

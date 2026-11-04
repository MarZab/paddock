---
id: PAD-69
title: Image builds copy only what the build context's .dockerignore lets through
status: Done
assignee:
  - '@claude'
created_date: '2026-11-03 16:28'
updated_date: '2026-11-04 15:07'
labels:
  - images
  - security
dependencies: []
documentation:
  - doc-7
  - doc-11
priority: medium
ordinal: 69000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reported from a .NET + pnpm monorepo (19 GB at the root: bin/obj, .tmp, node_modules, .pnpm-store, .git) whose Dockerfile needs only the root mise.toml. Today `ImageBuilder.build` runs `sbx cp <buildContext> builder:/tmp/paddock/ctx`, which copies the whole folder; `.dockerignore` only takes effect afterwards, inside the builder, when `docker build` reads it from the copied context. So `buildContext = "."` is unworkable for large repos, and files the image never needs (including a root `.env` with secrets) reach the builder sandbox. The per-Dockerfile ignore file (`<Dockerfile>.dockerignore`, BuildKit) is not applied at all, because the Dockerfile is copied alone to /tmp/paddock/dockerfile/. Projects work around this with a small build folder plus a generated copy of the root files. With `[images] builder = "docker"` (the Mac's Docker, no copy) both ignore files already work as docker defines them. Prefer honouring .dockerignore over new `[image] include/exclude` keys: one syntax, the same one docker build uses, and the host-Docker path already behaves that way.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 With a builder sandbox, files and folders excluded by the build context's .dockerignore never reach the builder (no copy, no temp staging of their content)
- [x] #2 <Dockerfile>.dockerignore next to the Dockerfile takes precedence over the context's .dockerignore, as in BuildKit
- [x] #3 Pattern semantics match docker's (Go filepath.Match plus **, leading / ignored, ! exceptions with last match winning, excluded directories re-entered for exceptions); fixture-style tests cover each rule, including a monorepo case that lets only mise.toml and tools/sandbox/** through
- [x] #4 Symlinks inside the context are not followed out of the project folder; a symlink pointing outside is skipped or refused, with a test
- [x] #5 Any host-side staging folder is private (0700), lives outside the project, and is removed afterwards, also on failure
- [x] #6 The Log shows how much was copied (files, bytes) so an operator can see the ignore file worked
- [x] #7 backlog doc Custom images and Project config file say when .dockerignore applies (at copy time for the builder sandbox, by docker for the host builder) and that the builder sees nothing else
- [x] #8 `[image] dockerignore = "path"` in .paddock.toml names the ignore file (inside the project, a file, same path rules as dockerfile); it takes precedence over <Dockerfile>.dockerignore and the context's .dockerignore
- [x] #9 Builds with the Mac's Docker ([images] builder = "docker") get the same filtered context and the same ignore file as the builder sandbox
- [x] #10 The setup kit's agent instructions and example .paddock.toml explain .dockerignore, the dockerignore key, and that the context can be the repo root with an ignore file
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. DockerIgnore (PaddockCore/Projects/BuildContext.swift): parse a .dockerignore as moby/patternmatcher does (trim, # comments, ! exceptions, filepath.Clean, leading / dropped), compile patterns to regexes (* [^/]*, ? [^/], ** any segments, \ escape, [..] classes), match a path or any parent dir, last match wins.
2. BuildContext.ignoreFile: <Dockerfile>.dockerignore next to the Dockerfile, else <context>/.dockerignore, else none.
3. BuildContext.stage: walk the context without following symlinks, skip excluded dirs unless an exception pattern can reach inside, clone included files (FileManager.copyItem, clonefile on APFS) into a 0700 temp folder outside the project, keep relative symlinks that stay inside the context, skip absolute or escaping ones and special files; return counts and bytes.
4. ImageBuilder.build: stage, sbx cp the staged folder (not the project path), copy the effective ignore file next to the Dockerfile in the builder so docker applies the same rules, log the copy stats, remove the staging folder in defer.
5. Tests: matcher rules, ignore-file choice, staging (monorepo case, symlinks, permissions, cleanup), builder call sequence.
6. Docs: Custom images and Project config file.

7. Operator asked (mid-task): [image] dockerignore key, precedence over the BuildKit files; Mac Docker builds use the same staged copy (docker build has no flag for an ignore path); setup kit instructions updated.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Builds read a staged copy of the context (BuildContext.stage, DockerIgnore); sbx cp and the Mac's docker build never see the project folder. AC7 changed in effect: with the operator's dockerignore key, the Mac's Docker also builds from the staged copy (docker build has no flag for an ignore path), so both builders apply the ignore file at copy time; the docs say so. Pattern compiler follows moby but escapes regex characters (+, (, |) that moby leaves live. Links: kept only when they stay inside the context as written and per realpath(3); dangling ones only without "..". The tag includes the dockerignore path only when set, so existing images keep their tags. No swiftlint config is in the repo, so lint was not a gate; swift test: 516 PaddockCore, 31 PaddockShell, all pass.

Obsolete (PAD-73.4, 2026-11-04): Paddock no longer builds project images. A project's own v3 kit has a dockerfile that sbx builds itself at create, and a change to the kit's files changes its fingerprint, which asks the operator again and lists a recreate item.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Image builds now copy only what the ignore file lets through. Before a build, Paddock stages the build context into a private temp folder (0700, removed afterwards, also on failure), applying docker's .dockerignore rules at copy time, so excluded files (build output, node_modules, .git, .env) never reach the builder sandbox. The ignore file is the new `[image] dockerignore` key when set, else `<Dockerfile>.dockerignore`, else the context's `.dockerignore`. It is staged next to the Dockerfile under the name docker checks first, so docker applies the same rules again. Mac Docker builds use the same staged copy. Links that lead out of the context are skipped and named in the Log, which also shows files, bytes, and how many entries were left out. The setup kit tells agents how to use a repo-root context with an allowlist ignore file. Docs: Custom images (Build context) and Project config file. Follow-up: PAD-70 (rebuild when a copied file changes). Not yet verified on the Mac with a real sbx build: does sbx cp copy a staged folder with links the same way?
<!-- SECTION:FINAL_SUMMARY:END -->

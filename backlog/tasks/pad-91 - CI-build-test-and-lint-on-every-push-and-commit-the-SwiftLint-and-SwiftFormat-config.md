---
id: PAD-91
title: >-
  CI: build, test and lint on every push, and commit the SwiftLint and
  SwiftFormat config
status: In Progress
assignee: []
created_date: '2026-11-04 18:43'
updated_date: '2026-11-07 08:10'
labels:
  - tooling
  - ci
dependencies: []
priority: medium
type: chore
ordinal: 96000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Review 2026-11-04. There is no .github, so nothing runs mise run test or mise run lint besides the operator's own machine, and there is no .swiftlint.yml or .swiftformat in the repository, so lint rules are whatever the pinned defaults are and strict mode treats them as the project's choice only by accident. Package.resolved files are committed (good) but nothing checks them.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A GitHub Actions workflow on a macOS runner runs mise install, mise run lint, mise run test for both packages, and builds the app; the first-build plugin trust step is handled without -skipPackagePluginValidation (CLAUDE.md)
- [ ] #2 A Linux job runs the PaddockCore tests (the sandbox flow in CLAUDE.md already supports it)
- [ ] #3 .swiftlint.yml and .swiftformat are committed with the reasons for any disabled rule, and cover Packages, App and tests
- [ ] #4 Workflow pins actions by commit SHA and sets permissions: contents: read
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Added .github/workflows/ci.yml (macOS lint+test, Linux test), .swiftlint.yml (paths only), shellcheck now also covers tools/sandbox/*.sh. Not done: app build in CI (needs SwiftTerm plugin trust), SHA-pinning of actions (SHAs not looked up), .swiftformat. Workflow never run.

2026-11-06 first CI run (c3dec2c) failed on both jobs. macOS: the macos-15 image defaults to Xcode 16.4 (Swift 6.1), which cannot resolve swift-crypto 5 (tools 6.2); the job now sets DEVELOPER_DIR to Xcode_26.3. Linux (4-core runner, every test in flight at once): tight time bounds and fixed sleeps failed under load. UnixSocketTransport and LlmmanAPI tests now check the error is a refused/missing connect rather than a timeout, with a loose bound; SandboxWatchers tests poll instead of sleeping and their fake watchers live 60 s and take their sleep along on SIGTERM; NodeScript tests retry a run that hits ETXTBSY (another test's fork holding the script's write descriptor). Verified with 5 full runs pinned to 2 cores next to a CPU hog.

2026-11-06 second macOS run (d42de21, Xcode 26.3, macos-15) hung: PaddockCore killed by the 600 s watchdog. The log cannot show where (swift test's stdout is block-buffered into the pipe), but the runner's orphan cleanup found three sh and one cat started by the test process: the VoiceKit and AgentStatusKit watcher tests started their endless /bin/sh loop with plain Process.run() from a worker thread, the loop inherited a mask with SIGTERM blocked (PAD-30), ignored the 2 s terminate, and readDataToEndOfFile never got EOF. Tests now stop watchers with Process.stop(after:) (Support/StopAfter.swift): SIGTERM, then SIGKILL 2 s later; a test covers a program that ignores SIGTERM. Not yet confirmed on CI. Also seen: test.sh stop_tests pattern does not match macOS's swiftpm-testing-helper, so a killed run leaves it behind.

The macOS job now runs on macos-26 with Xcode 26.5, the operator's Xcode (MacOSX26.5 SDK, Swift 6.3.3); macos-15 has no Xcode past 26.3.

2026-11-06 third macOS run (b99efb5, macos-26, Xcode 26.5) still hung; left behind three bash and swiftpm-testing, no cat. So the watcher tests were not (or not the only) cause. The watchdog now runs tools/tasks/lib/hang-report.sh before killing: every process below the run with its age and command line, and on macOS a 3 s sample of the test process with the test-target frames printed (full samples next to the log). stop_tests now also matches swiftpm-testing-helper. CI uploads .tmp/test-runs as an artifact when the job fails.

2026-11-06 the hang report (PR #1 run) named it: the test helper's only children were the stop(after:) test's sh (trap '' TERM) and two paddock-voice-watch loops, all 4:56 old. So the stop timer never fired, not even its SIGKILL: DispatchQueue.global().asyncAfter did not run in the test process on the 3-core runner. stop(after:) now times on a Thread of its own and signals the pid with kill(2). The report's test-process match skipped swiftpm-testing-helper (its name contains swift-test), so no sample was taken; fixed. To check: LineStreamer waits for exits on DispatchQueue.global(qos: .utility), which may starve the same way in the app.

2026-11-07 fourth macOS run (8c91ffc) no longer hung but failed two tests: the runner stalled every test about 13 s, longer than the commands they relied on. cancellingReturnsAtOnceAndEndsTheProcess slept 200 ms before cancelling a 'sleep 2; touch' (it finished first, exit 0); terminateAllEndsRunningStreams's 'sleep 10' ended between 'up' and the count. The cancel test now waits for the child's pid and checks it is gone, with a 60 s child; the streamer's child sleeps 120 s; their time bounds are 20 s. Not yet confirmed on CI.
<!-- SECTION:NOTES:END -->

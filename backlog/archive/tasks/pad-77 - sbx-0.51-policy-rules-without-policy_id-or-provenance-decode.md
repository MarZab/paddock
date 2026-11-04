---
id: PAD-77
title: 'sbx 0.51: policy rules without policy_id or provenance decode'
status: Done
assignee: []
created_date: '2026-11-04 12:47'
updated_date: '2026-11-04 12:47'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 82000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
On sbx 0.51.0, `sbx policy ls <sandbox> --json` lists the implicit `default-deny-all` rule with neither `policy_id` nor `provenance`. SbxPolicyRule required both, so the whole list failed to decode. That affected every place Paddock reads a sandbox's rules: the Network page, Sync, and host rules. Found in the PAD-73.1 capture on the operator's Mac.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 SbxPolicyRule decodes a rule without `policy_id` or `provenance`; `createdVia` reads `implicit` for it
- [x] #2 The Rules table shows such a rule as one of sbx's own defaults
- [x] #3 A fixture from sbx 0.51 (Fixtures/sbx/policy-ls-v3-sandbox.json) decodes in a test
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
policyId and provenance are optional on SbxPolicyRule. A computed createdVia falls back to "implicit", and the Rules table maps that to sbx defaults. SandboxSync, ProjectRunner, and the tests use createdVia. Sanitized 0.51 fixtures for `policy ls` and `sbx ls` (ls-v3.json) have decode tests. Full swift test passes on Linux (571). Not run in the app on the Mac.
<!-- SECTION:FINAL_SUMMARY:END -->

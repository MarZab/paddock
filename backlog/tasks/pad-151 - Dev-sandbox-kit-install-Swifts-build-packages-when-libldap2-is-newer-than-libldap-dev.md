---
id: PAD-151
title: >-
  Dev sandbox kit: install Swift's build packages when libldap2 is newer than
  libldap-dev
status: Done
assignee:
  - '@claude'
created_date: '2026-11-25 07:30'
updated_date: '2026-11-25 07:31'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 157000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Recreating this repo's sandbox failed in the kit's Swift step: libcurl4-openssl-dev pulls libldap-dev, which pins libldap2 to its own exact version, and the image already had a newer libldap2 from DHI, which apt will not downgrade on its own. The operator fixed it on 2026-11-25.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 tools/sandbox/paddock/paddock.yaml installs libldap2 at libldap-dev's candidate version with --allow-downgrades, so the step works while the repo is inconsistent and is a no-op once it is not
- [x] #2 The operator recreated the sandbox with it
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The dev sandbox kit asks for libldap-dev's own libldap2 version (with --allow-downgrades) before Swift's build packages, so a newer libldap2 in the image no longer breaks the install; the operator's fix, used to recreate this sandbox.
<!-- SECTION:FINAL_SUMMARY:END -->

# Release tool access implementation plan

Use superpowers:executing-plans inline; no subagents.
Spec: ../specs/2026-10-02-release-tool-access-design.md
Base: #234 / 4b65b8c, with #108/#112 implemented in attached Drafts.

## Task 1: Data-preserving secondary routes

- [x] Observe RED: General hides saved genre/characters.
- [x] Observe RED: real toolbar search/menu accessibility; truthful tool labels.
- [x] Add shared secondary menu and primary native source-search button.
- [x] Retain existing writer information in General without creating new Fiction setup.
- [x] Demote legacy tabs; update UI smoke selectors without weakening assertions.
- [x] Record old/new routes and retention rationale in the release audit.
- [x] Focused/full tests, app and MINTBench builds, release bundle.
- [x] Isolated no-model launch/normal-quit smoke.
- [x] Inline review and prepare commit/Draft text; delivery recorded in the local ledger.

Delivery: commit, push, Draft PR and attach. No CI/merge wait or owner checks.

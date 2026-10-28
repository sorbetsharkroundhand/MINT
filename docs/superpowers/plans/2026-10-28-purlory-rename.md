# Purlory Rename Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement inline. The owner has explicitly selected full renaming; proceed without another scope approval.

**Goal:** Rename all owned product and implementation identities to Purlory with preserved access to previous user data.
**Architecture:** Mechanical identifier/path migration plus a small legacy preferences boundary; retain the existing verified project importer. Validate icons separately from third-party notices.
**Tech Stack:** Swift, SwiftUI/AppKit, SwiftPM/Xcode, Python, shell.
**Spec:** docs/superpowers/specs/2026-10-28-purlory-rename-design.md

## Global Constraints
- No in-place manuscript migration, third-party byte changes, or weakening CI.
- New identifier app.purlory.Purlory; new storage Documents/Purlory.
- Keep original icon inputs and previous data intact.

## Review Focus
- Renamed package resource bundles must match runtime lookup and notices inventory.
- Previously saved preferences must not overwrite new preferences or re-enable AI without consent.
- Existing project import must preserve original sources and reject symlinks.
- Icon validation must reject missing, malformed, or incomplete resources.
- Required CI context renames must be reflected in repository protection if configured.

### Task 1: Identity and packaging
- [x] Add a regression checking the SwiftPM product, Xcode scheme, and icon validation behavior; observe failure.
- [x] Rename owned text and paths across source, tests, scripts, manifests, CI, and docs. Preserve upstream bytes and historical evidence.
- [x] Add scripts/validate-purlory-icon.py and wire developer/archive validation.
- [x] Run offline packaging regressions and resolve all resource/hash references.

### Task 2: Previous-installation compatibility
- [x] Add missing-only preference migration tests before implementation, including false values, existing new values, repeated imports, and unrelated defaults.
- [x] Add Sources/PurloryCore/Storage/PurloryPreferences.swift, initialize before runtime settings, and preserve explicit old-project import access.
- [x] Run preference, storage, legacy migration, and project import tests.

### Task 3: Delivery verification
- [x] Run swift build, swift test, swift build --product PurloryBench and packaging checks.
- [x] Build Purlory.app and verify its identity/icon/resources; record any unavailable native/Store verification truthfully.
- [x] Rename GitHub repository, update origin, and inspect required checks for stale names.
- [x] Review full diff, scan remaining identity references, and record results.

## Execution record

Completed inline. See `docs/release/purlory-rename-verification-2026-10-29.md` for actual test evidence and the Xcode plist failure/fix. Existing data import remains explicit across sandbox boundaries; no original manuscripts were moved. The active checkout directory is retained to preserve its Codex attachment.

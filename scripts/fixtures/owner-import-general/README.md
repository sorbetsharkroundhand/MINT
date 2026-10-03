# Synthetic owner import fixture

Select this folder in **File > Import project**, then choose **General**.
The imported project contains **문서 A** and **문서 B**, with Korean text and
chapter/scene headings for the later search, navigation and persistence checks.
No model or real manuscript is required.

`entries.json` uses the legacy archive envelope (`entries`, `activeID`,
`folders`, `expandedFolderIDs`) and ISO 8601 dates used by `EntryStore` exports.
A bare entry array or numeric date is not a MINT legacy archive. The original
2026-10-03 owner kit mistakenly used both and failed before activation.

`ImportProjectCoordinatorTests.testOwnerFixtureImportsAndReopensWithoutChangingSource`
imports this exact file through the production folder coordinator into temporary
storage, checks both documents' original text/titles/IDs and General mode, reopens
the persisted project, and checks that importing did not change the source bytes.

When preparing an owner test kit, copy this `entries.json` verbatim into its
`fixtures/import-general` folder instead of hand-generating another archive.
Refresh the kit's fixture hash after copying. An existing developer app containing
the import coordinator can use the corrected fixture without rebuilding.

For the later editing-position test, click inside existing text without editing,
switch documents and reopen normally; separately repeat with a text selection.
Saving a position must not require Backspace, an inserted/deleted character, or
forcing an IME composition to finish. Report composition and position restoration
as separate observations.

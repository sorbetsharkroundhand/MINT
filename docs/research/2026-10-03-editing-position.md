# Editing-position and composition research

Owner request, 2026-10-03: do not make Backspace or a throwaway edit necessary to
remember a position in the middle of a document. Investigate Notion and Word.
This note records public evidence and local code findings; it does not claim
hands-on validation of either installed app or disclose their private internals.

## Public evidence

| Product / platform | Confirmed behavior or representation | Limits |
| --- | --- | --- |
| Word | The public Selection model represents a selection with starting and ending character positions. `Application.GoBack` visits the last three editing locations; Word for Mac documents Shift-F5 for the previous insertion point. | Edit history is distinct from the last position clicked without an edit. These APIs do not specify the private format of restart position storage. |
| Notion | Its engineering article describes uniquely identified blocks, and its help documents anchor links to individual blocks. | These sources do not describe character-level caret persistence, caret restoration after restart, or IME state retention. A block link alone does not prove these guarantees. |
| Word Online example / browser input | Chrome's EditContext article describes an IME hazard in Word Online: updating the active editing DOM can cancel composition, so collaborative updates wait for composition to finish. EditContext separates input from rendering. | This is a published web example, not proof of the current Word for Mac implementation or that Word currently uses EditContext. |
| macOS AppKit | `NSTextInputClient` exposes marked text and selection separately; `setMarkedText` supplies the marked string and its selection. NSTextView reports selection changes through a notification. | Live composition belongs to the input session. A saved document position is a different kind of state. |

Sources, accessed 2026-10-03:

- [Word Selection.Start](https://learn.microsoft.com/en-us/office/vba/api/word.selection.start)
- [Word Application.GoBack](https://learn.microsoft.com/en-us/office/vba/api/word.application.goback)
- [Word keyboard shortcuts, including the Mac tab](https://support.microsoft.com/en-us/accessibility/word/keyboard-shortcuts-in-word)
- [Notion's block data model](https://www.notion.com/blog/data-model-behind-notion)
- [Notion writing and editing basics](https://www.notion.com/help/writing-and-editing-basics)
- [Chrome: EditContext and the Word Online composition example](https://developer.chrome.com/blog/introducing-editcontext-api)
- [AppKit NSTextInputClient](https://developer.apple.com/documentation/appkit/nstextinputclient)
- [AppKit selection-change notification](https://developer.apple.com/documentation/appkit/nstextview/didchangeselectionnotification)

## MINT's current behavior

`MintBlockEditor.Coordinator.textViewDidChangeSelection` already records an
unmarked selection without requiring a text edit. `WritingPositionStore` stores
the project/document identity, UTF-16 position, selection length, and adjacent
text context in UserDefaults. It debounces writes and flushes on normal quit.
Restoration checks the saved context and can re-anchor after preceding edits.

The store ignores marked snapshots. That guard protects the last stable saved
position; it is not an instruction to commit composition with Backspace. Native
marked text should remain owned by the live NSTextView/input session. The current
document-transition code explicitly unmarks outgoing text, so tool transitions,
document switches and process restart must be tested as separate cases rather
than assuming each preserves an unfinished IME session in the same way.

Inference for future work: track a stable document identity and selection as
UI state, independently of manuscript edits. Keep composition state separate and
avoid replacing the active native editor while a transient tool opens. The
public Notion model suggests stable block anchors as one possible representation,
but its actual caret implementation remains unverified. No editor behavior was
changed in this fixture repair.

## Revised owner check

1. Import the corrected synthetic General project. In A, click between existing
   characters without typing or deleting. Switch A to B to A; check the exact
   caret position and visible paragraph.
2. Repeat with a nonempty text selection. Quit normally and reopen using the
   isolated test launcher; check restoration independently of document changes.
3. Separately compose Korean normally and open/close a transient tool, then keep
   typing. Observe character continuity, selection and undo. Do not force
   composition to finish as a workaround for a failure.

Backspace is an editing key to test separately when useful, not a command to
record a position. No dummy insertion/deletion should be required by this check.
Owner step 1 passed; the originally supplied import fixture failed step 2.
The corrected import has automated coverage; owner confirmation remains pending.

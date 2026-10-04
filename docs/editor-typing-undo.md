# Typing Undo boundaries (#191)

## Reproduction and cause

On main `093683b`, the ProjectSession editor coalesced adjacent native typing
across spaces, paragraph breaks, and idle time. Typing
`First sentence. Second sentence.` into an empty document and undoing once
returned an empty document. `Earlier\nRecent` and two bursts separated by
10 seconds of keyboard event timestamps likewise returned an empty document.
Moving the caret before another edit already created a native boundary.

The editor relied entirely on NSTextView coalescing; it did not end typing
units at word/paragraph boundaries or when a writer resumed after a pause.
The ProjectSession binding and save path were not registering whole-document
undo snapshots. The relevant native typing overrides date from the #167
runtime path; reproduction here uses the integrated current runtime.

The regression harness hosts the real ContentView/ProjectSession editor and
delivers native keyDown events with `UndoManager.groupsByEvent = true`. It
drains each event's automatic group before continuing. The existing explicit
test groups with `groupsByEvent = false` produce character-sized undo actions
and cannot reproduce this particular native coalescing failure.

## Behavior

- Committed whitespace ends the current typing unit, usually a word and its
  following space.
- Return ends the preceding unit, including the paragraph break.
- A keyboard gap of at least two seconds starts a new unit before the next
  event. This uses event timestamps, with no timer or background task.
- Live marked text never triggers the idle boundary; whitespace is considered
  only after native text insertion has completed and marked text is absent.
- Native selection, replacement, undo/redo, and document-transition behavior
  remain owned by AppKit and the existing ProjectSession editor bridge.
- Save/flush timing does not split a typing unit.

The implementation uses Apple's
[breakUndoCoalescing API](https://developer.apple.com/documentation/appkit/nstextview/breakundocoalescing%28%29)
to end native coalescing rather than registering manuscript snapshots.

## Verification

`TypingUndoTests` covers the reproduced failures, caret relocation and redo
selection, a 36,000-character manuscript, A → B → A undo/redo isolation,
synthetic Hangul marked-text updates and commit, save-independent grouping,
and termination flush followed by ProjectSession bootstrap.

The packaged UI smoke types two words in a new document, sends real ⌘Z and
⇧⌘Z, checks the exact resulting body, then verifies canonical persisted
content and normal quit/relaunch using the existing isolated-home flow.

## Owner verification still required

Use an isolated test project in the candidate app. Type several paragraphs
with real Korean IME, pause during composition, move the caret, replace a
selection, and inspect repeated Undo/Redo. Repeat after A → B → A and normal
quit/relaunch. Check Ghost Tab/right-arrow/Escape while writing. The automated
marked-text fixture does not establish the feel of a real input method.

This implementation does not close #191 or satisfy its owner checkbox.

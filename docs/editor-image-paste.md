# Standard clipboard image paste (#192)

## Reproduction and cause

On main `491fc14`, the real ProjectSession editor rejected the standard Paste
command for a clipboard containing only PNG, TIFF, or JPEG data. Its plain-text
NSTextView configuration did not advertise image pasteboard types, so native
menu validation disabled Paste before the existing image handler could run.

The issue's original observation that only PNG was supported no longer matched
this checkout: `insertImages(from:)` already accepted PNG and converted TIFF to
PNG. On the tested macOS host, a JPEG-only pasteboard also supplied an AppKit
TIFF conversion. Calling the old `paste` override directly therefore missed the
actual failure in standard command validation.

The editor now advertises the MINT image object and PNG/TIFF/JPEG types through
[readablePasteboardTypes](https://developer.apple.com/documentation/appkit/nstextview/readablepasteboardtypes).
Native Paste and direct pasteboard reads both enter the existing managed image
importer through `readSelection(from:)`. Advertising types alone was insufficient:
a regression test demonstrated that native reads could bypass managed storage.

Internal MINT metadata takes priority over bitmap representations. Ordinary text
continues through native NSTextView insertion. Image decoding, asynchronous
project/selection validation, asset storage, and image controls retain their
existing paths. Read-only editors reject pasteboard reads.

## Automated coverage

`ClipboardImagePasteTests` hosts the real ContentView/ProjectSession editor and
checks:

- Native Paste enablement for PNG, TIFF, and JPEG, and rejection when read-only.
- PNG/TIFF/JPEG and NSImage-written clipboard insertion at a middle caret.
- Managed image bytes, decoded dimensions, one Undo/Redo, caret placement, and
  termination flush followed by ProjectSession bootstrap.
- Internal image alt/title/width/alignment preservation and text-only Paste.
- Direct native pasteboard reads importing through managed project storage.

The UI smoke offers a synthetic PNG-only system clipboard, sends real Cmd-V,
checks one Cmd-Z/Shift-Cmd-Z, then verifies the persisted asset hash and exact
manuscript after normal quit/relaunch. The fixture retains the prior clipboard
only in memory and restores it unless the user copied something newer. Both
test paths use isolated projects; the UI smoke uses `CFFIXED_USER_HOME`.

## Owner verification

In an isolated project, copy a screenshot, a Preview selection, and a browser
image, then paste each using Cmd-V or Edit > Paste. Check visible rendering,
alignment, resize, copy, delete, Undo/Redo, and normal quit/reopen. Synthetic
pasteboards establish the supported representations; they do not replace this
check of real source applications and the image controls.

This change does not satisfy the owner checkbox or close #192 before merge.

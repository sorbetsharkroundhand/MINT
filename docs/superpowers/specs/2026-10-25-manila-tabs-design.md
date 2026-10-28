# Manila folder tabs

Implement the owner's supplied three-stage design on `codex/purlory-editorial-redesign`, preserving existing uncommitted work. Document slots contain ordered document IDs and one visible tile; tool slots remain singletons. Decode legacy slots without tabs as singleton binders. Opening selects an existing tab anywhere or appends to the active document's binder. Explicit “spread all” remains a comparison command.

Use the existing AppKit canvas and sibling document hosts. Retain hidden tab editors to preserve selection, scroll and undo. A native, horizontally scrollable tab strip draws a 30pt active paper tab with 6pt outward fillets and no bottom border. Following the owner's connected-tab revision, inactive labels blend into the bar with vertical separators between adjacent inactive labels, without individual boxes. Include hover close, middle click close, new document, typewriter and focus controls. Quiet typing dims inactive tabs and plus to 0.35. Respect Reduce Motion.

Tab-strip drops reorder or merge; body-edge drops use existing column/row insertion. Cancel restores the exact original layout. Persist only committed layouts and reject stale project drags. Closing chooses a neighboring tab and never closes the last open manuscript. Tab membership is presentation state, not manuscript ownership.

Approaches: replacing the canvas or recreating one editor per selected tab would risk existing drag and editor state. Extend slots and retain existing hosts instead, as requested. Native tab controls keep pointer tracking, accessibility and existing canvas drag capture together.

Validation: deterministic legacy decode, normalization, opening/closing, split/merge/reorder/cancel/project isolation tests; native host identity, cursor/scroll/undo, controls and narrow-width tests. Run Swift build, test and benchmark compile. Final subjective app/real IME checks remain owner verification under the release policy.

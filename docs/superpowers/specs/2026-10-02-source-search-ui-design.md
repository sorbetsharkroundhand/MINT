# Temporary model-free source search (#112)

Consume the exact scoped originals and native jump/return from #108. The current
issue supersedes historical Ask MINT/agent/LLM breadth. Standing user authority
selects continuous inline implementation, no approval pauses or subagents.

Use a temporary native NSPanel with NSSearchField, scope popup (Here/Chapter/Project),
scrollable original result list, open and close actions. Command-K invokes it;
Escape closes; arrows select; Return opens. Keep marked text with its input client,
do not interpret composition keys as navigation. Default scope Project; the writer
can explicitly narrow. Native system colors/fonts and opaque standard controls
support appearance/accessibility without changing palette, fonts or editor layout.

Alternative SwiftUI sheet adds modal ownership; a shell overlay adds layout/focus
coupling. A native child panel keeps the existing opaque manuscript/editor stable.
Bound width to the parent window with a 360pt floor and bounded result labels.
No animation, permanent chat, model setup, network, search history or query logging.

Search snapshots run in a cancellable detached task with 120ms typing debounce.
Bind each surface to the full runtime identity plus a monotonically increasing
query ticket. Clear old results immediately. Project/document/generation changes,
transitions and dismissal cancel work and prevent late publication, including A→B→A.
The native panel closes on ownership invalidation and returns focus to the current
editable manuscript. Search source-return preserves the earlier native position;
provide a separate return action after the search surface closes. Stale source
navigation errors are visible and never quietly choose another quote.

Automate real controller cancellation/scopes and native panel key/action/accessibility
boundaries. Actual unlocked interaction, Korean IME feel, VoiceOver and wording
remain owner verification. CI/merge and Store signing are not local proof.

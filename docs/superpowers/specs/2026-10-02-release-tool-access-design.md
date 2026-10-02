# Release tool access (#186)

After #108/#112 provide original search and native source return, expose search
in the writing toolbar. Retire the primary Fiction/Bible badge and advanced tool
tabs. Keep a single secondary menu, "Saved settings and records", for information
that source search cannot replace. Use direct menu items, stable accessibility
identifiers and existing panel ownership; no nested menus or new workspace modes.
Use a native NSButton and NSPopUpButton with system appearance and explicit labels.
They refuse first responder so a toolbar click preserves the manuscript caret
before native search captures it. Menu selection changes stored presentation only.

Retain character/genre data, author overrides, decisions, recorded conversations
and context choices. Existing Fiction fields remain accessible after changing a
project to General; a blank General document does not advertise Fiction setup.
No migration or data deletion. Generic project storage remains domain-independent.

Use the same compatibility menu in the explicitly opened legacy workspace. Keep
its existing data surfaces and the File menu library route. Empty Living Margin
stays hidden. No Map/Review/Ask MINT or model activation. Native search controls
follow system appearance, and opening/closing tools preserves editor state.

Current #186 permits secondary compatibility routes; historical removal-only
interpretations of #117 do not supersede that contract. The standing human
instruction authorizes inline implementation and stacked Drafts without awaiting
main merge, CI or a new design approval. Owner data-reachability and actual
IME/VoiceOver checks remain pending.

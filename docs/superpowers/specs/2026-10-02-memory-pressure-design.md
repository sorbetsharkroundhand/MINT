# Memory pressure policy (#182)

Refreshed #182 has no recent comments or active competing implementation PR.
Its current-behavior paragraph predates #177: ModelMemoryPolicy already rejects
declared peaks above 60% of the smaller physical/Metal recommended working set
before model load. Preserve that policy/catalog and its regression coverage.
The missing behavior is reacting to runtime pressure. User authorizes inline M2
implementation while deferring owner real-device checks and CI.

Use injectable normal/warning/critical events. Warning pauses/cancels background
indexing and optional original-name preparation first. Critical additionally blocks
new model work, cancels foreground completion/preload/naming, then drains/releases
the resident engine through its existing unload lifecycle. Preserve manuscripts,
writer decisions, derived snapshots and on-disk model/cache files. Editing and
durable saving continue. Do not disable the user's AI preference or approve models.

Normal pressure permits background work again. Completion stays blocked until
an in-flight release finishes; never reload automatically. Duplicate/escalated
events cannot start competing unloads or let an old finalizer unblock newer work.
Expose a clear temporary-memory message via existing app status. Production listens
to DispatchSource memory-pressure events; tests inject events and paused release
callbacks, requiring no real pressure, network, weights or user manuscripts.

Owner observation on a constrained real Mac remains pending. No issue checkbox,
merge, release/default/model/license decision, CI wait or subagent is authorized.

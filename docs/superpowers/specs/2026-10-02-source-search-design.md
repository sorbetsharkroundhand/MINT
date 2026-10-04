# Deterministic source search (#108)

Current issue #108 supersedes the historical structure/vector retrieval plan.
Extend the existing project search/navigation flow without a model, disk scan,
derived summaries or a new mutable project owner. This is the first M3 contract;
#112 consumes it, and #186 follows that usable replacement.

Search immutable WritingProject values on explicit invocation off the editor hot
path. Here means the current parsed scene segment; Chapter means its contiguous
chapter group (heading path prefix of two, existing HierarchicalMemory semantics);
Project means visible documents in their stored order. With no headings Chapter
is the current document. Inspection may read forward. The separate beforeCursor
purpose restricts earlier documents and clips the current body before parsing or
matching; it never returns future quote context. Invalid ownership returns empty.

Literal case-insensitive matches outrank alias expansions. Expand only names and
comma-separated aliases of writer-owned cards with autoRegistered != true, and
only when the query identifies one card unambiguously. Never use descriptions as
evidence. Every result carries an original EvidenceAnchor, exact matched text,
explicit reason and deterministic alias/document/offset tie-breaks. Limit output to 100.

SourceAnchor resolves the entire exact quote. A still-valid hint disambiguates
duplicates only on the original content revision; after edits a unique exact
quote can re-anchor, while removed or ambiguous quotes are explicitly stale.
No fuzzy fallback may quietly select unrelated prose.

Subsequent source navigation captures project/document, native selection and clip
origin before leaving writing; restores them on return; rejects stale ownership,
marked text and edited return snapshots. Keep Markdown/storage coordinates
separate and native undo/editor identity intact. #112 provides temporary native
keyboard search, not chat. Owner relevance/IME/VoiceOver/feel and CI stay pending.

Alternatives rejected: extending document-only Navigator results cannot represent
several passages; a vector/summary pipeline adds dependencies outside this release.
Standing user instruction authorizes inline implementation without approval pauses.

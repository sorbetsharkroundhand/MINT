# Implementation plan — #18

Spec: [Bounded dirty render design](../specs/2026-10-02-dirty-render-design.md).

- [x] 1. Pure paragraph index with UTF-16 range lookup/local replacement and math-run
  boundaries. RED/GREEN semantic splice/query and long-document bounded-work tests.
- [x] 2. Wire index and dirty scopes to authoritative editor storage, including
  attributes, structural edits, programmatic load and undo. Reject stale assumptions.
- [ ] 3. Bound ordinary render, inline folding, marker tracking and group cleanup to
  dirty/visible/selected/group neighbors. Preserve existing round-trip/render tests.
- [ ] 4. Record focused 300k/100-media typing/scroll/memory evidence, full/build/bench
  and developer-bundle smoke; defer owner native feel/IME and continue #183.

Per-slice RED, focused/full/build/bench and author review before bounded Draft PR.
Do not duplicate already-landed scroll/LRU/downsample work, use subagents, wait for
CI/merge, modify original checkout or claim owner checks.

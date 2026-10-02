# Implementation plan — #181

Spec: [Ghost context design](../specs/2026-10-02-ghost-context-design.md).
Inline execution and author review follow the user's no-subagent instruction.

- [x] 1. Add explicit A/B/C assembly and report strategy with default C unchanged.
  Test raw isolation, instruct budget, long unbroken/Unicode suffixes and fallback B.
- [x] 2. Prepare cancellable, revision-memoized original-name sentence evidence.
  Test ambiguity, Korean boundaries, latest prior selection, UTF-16 ranges,
  exclusions, budget pressure and stale scope/body. Integrate background ownership.
  Original extraction/selection delivered first; background ownership follows.
- [ ] 3. Wire immutable settings/controller parameters, expanded tokenizer-budgeted
  windows and opportunity-linked local strategy/latency metrics. Test changes during
  asynchronous prediction and partial acceptance; expose replay/settings/report UI.
  Runtime settings, app preparation callbacks and local opportunity metrics are
  implemented. Settings/report UI and explicit replay controls follow separately.
- [ ] 4. Review integration and deliver a batch handoff. Run necessary local build,
  full tests and bench compile per final slice. Keep owner A/B/C, CI, model/license
  and unlocked native UI evidence explicitly deferred.

Do not repeat native dependency archives per slice or wait for remote CI. Continue
to #182 after implementation is delivered, independent of GitHub merge status.

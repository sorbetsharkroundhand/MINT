# Implementation plan — #182

Spec: [Memory pressure design](../specs/2026-10-02-memory-pressure-design.md).
Inline execution and author review follow the user's no-subagent instruction.

- [x] 1. Add injectable pressure event source and policy coordinator. RED/GREEN
  warning/critical order, duplicate release, normal during draining, escalation and
  failed/late release. Deliver a bounded PR with full/build/bench verification.
- [x] 2. Wire background pause gates and completion cancellation/release lifecycle.
  Cover current ownership, no automatic retry/reload, preference/data retention,
  source preparation and load refusal. Reuse #177 policy; keep editor/session generic.
- [ ] 3. Start/stop the monitor with the real app runtime and expose temporary state.
  Verify integrated local build/full suite/bench and appropriate isolated launch;
  defer real-device pressure/CI/owner evidence, then continue #18.

Do not wait for remote CI, merge PRs, close issues, modify the original checkout,
weaken tests or tick owner checks. No native dependency archive per slice.

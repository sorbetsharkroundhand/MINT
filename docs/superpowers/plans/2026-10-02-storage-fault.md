# Implementation plan — #183

Spec: [Storage fault coverage](../specs/2026-10-02-storage-fault-design.md).

- [x] Add fresh-root failure matrix tests through the existing filesystem seam.
- [x] Implement reusable before-write/staged-replacement injection and verify hits.
- [x] Verify corrupt durable/derived inputs, migration and authoritative activation.
- [x] Prove hash-verification RED, run focused/full/build/bench/smoke, author review,
  commit/push/attach Draft PR, then continue #184.

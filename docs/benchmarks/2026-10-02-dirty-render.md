# #18 bounded dirty-render evidence

Production source e25cebd; deterministic generator in
`LongDocumentRenderMeasurementTests.swift` (fixture version 1). Raw samples and
body/asset hashes: [JSON](2026-10-02-dirty-render.json). Mac14,6 / Apple M2 Max /
32 GiB, macOS 27.0 (26A428), Swift 6.3.3, Xcode 26.6 (17F113), debug XCTest.
Run the focused test in a fresh process with isolated `CFFIXED_USER_HOME`/`HF_HOME`,
no models or real manuscripts. All 50 image references resolve through the
authoritative verified project asset catalog. There are 50 distinct 2048×1024 PNGs
and 50 distinct math blocks among 3,101 paragraphs. Source: exactly 300,000 Swift
characters / 312,000 UTF-16 code units, including Hangul and emoji.

| Observation | Result |
| --- | ---: |
| Synchronous typing/serialize/visible-layout p95, 40 samples | 1.035 ms |
| Explicit clip scroll + indexed refresh p95, 40 samples | 13.080 ms |
| Explicit full render p95, 10 samples | 501.798 ms |
| Cold load/render | 802.437 ms |
| First visible layout/render readiness after load | 136.451 ms |
| Process lifetime peak physical footprint | 87,691,368 bytes (83.6 MiB) |
| Ordinary typing render paragraphs | 6 of 3,101 |
| Scroll render paragraphs | 2–9 of 3,101 |

The full-render comparison is the current explicit full path on the same loaded
fixture; it is not a before/after native typing benchmark. Timings use monotonic
`DispatchTime`; p95 uses the existing editor `noteKeystroke` sorted-index convention
(`min(n−1, floor(n×0.95))`). Serialization is warmed once. Scroll samples cover the
full document height; dirty/caret/previous-selection neighbors remain included.
No absolute timing gate was invented: automated assertions verify bounded work,
unchanged index build count, exact media counts and successful asset resolution.

Peak memory uses #179/MINTBench's `ri_lifetime_max_phys_footprint`; the fresh focused
process includes test host, fixture generation, layout and all sampled render passes.
It is neither MLX memory nor an inference hardware-tier result. An unavailable
reading stays absent, never zero. #154 currently freezes AI evidence through its
children and contains no independent editor p95 threshold.

The first-visible metric includes explicit text-container layout and refresh after
load. It is a readiness proxy, not actual display paint. These synchronous AppKit
samples exclude SwiftUI/event-to-idle delivery, marked IME composition, real focus
interaction and subjective feel. No new async decoding subsystem is justified by
this bounded-work result; cold load and real macOS paint/feel remain owner evidence.

Regression proof: temporarily restoring global-scan scope caused all 80 ordinary
typing/scroll bounded-work assertions to fail (3,101 visited paragraphs). Restored
production source is byte-identical to e25cebd; this mutation result is not marketed
as an old-release latency measurement. Focused fresh-process run and full local
suite pass. Existing visible/LRU/downsample/round-trip/IME/Ghost/undo coverage remains
green. The #226 exact production developer bundle passed no-model launch/normal quit.

Reproduce (choose a new report destination; existing reports are never overwritten):

```sh
CFFIXED_USER_HOME="$PWD/.build/issue-176-home" \
HF_HOME="$PWD/.build/issue-176-home/hf" \
MINT_RENDER_REPORT_PATH="$PWD/.build/new-render-report.json" \
swift test --disable-automatic-resolution --filter LongDocumentRenderMeasurementTests
```

#18 remains open for merge/CI and owner native long-document validation. Continue
independent recovery coverage in #183; do not wait for those owner checks.

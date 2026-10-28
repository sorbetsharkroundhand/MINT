# Initial Korean correctness validation

Issue #126, approved implementation plan Task 6. Verified on 2026-10-16 with the pinned offline Kiwi v0.24.0 backend described in [backend validation](korean-backend-validation.md). This is a limited initial rule set, not general Korean grammar completeness or final native-editor acceptance.

## Production rules

`ko.correctness.doeda-past` requires the reviewed 되/VV + 었/EP + 다/EF signature and a matching native-derived local alternative for `됬다`. `ko.correctness.bound-noun-su` requires a verb/adjective, prospective modifier, bound noun 수, and existence/absence predicate. It promotes only the exact missing-space insertions also supported by the native alternative, including reviewed 먹을/갈/좋을/할 and front/back/both missing spaces. Whole-window joining is never a correction action; confidence remains uncalibrated (`nil`). Other native alternatives stay quiet.

Learned words suppress the affected full lexical entry, with canonical composition and exact case. A different unchanged learned word does not suppress the finding. Directly quoted lexical literals remain quiet; full dialogue can still receive correctness findings when dialogue style is disabled.

Analysis uses an NFC lookup view without modifying manuscript bytes. Proved normalization boundaries map every token/candidate back to original UTF-16. Admitted native calls are at most 1,024 units with at most 256 units of contextual overlap inside a 4,096-unit analysis window. Malformed/half-surrogate ranges are rejected before clamping. Oversized unsupported composed text is unassessed; the provider throws instead of returning apparent clean success. Later controller/report tasks must retain that failure/coverage distinction.

## Real-provider fixture observations

The copied [synthetic fixture corpus](../../Tests/PurloryCoreTests/Fixtures/KoreanDiagnostics/correctness.json) supplies original UTF-16 locations/lengths and alternatives. The real production provider produced all 18 required findings across 15 positive cases, and no correctness finding across seven negative cases. Tests assert exact original bytes, whole composed characters, native-derived alternatives, unique identities and `nil` confidence. Duplicate NFC/NFD occurrences are checked at separate exact positions. No fixture provider satisfies these assertions.

| Fixture | Expected correctness findings | Observed |
| --- | ---: | ---: |
| `typo` | 1 | 1 |
| `spacing` | 1 | 1 |
| `multiple` | 2 | 2 |
| `mixed` | 1 | 1 |
| `nfd-typo` | 1 | 1 |
| `nfd-spacing` | 1 | 1 |
| `already-correct` | 0 | 0 |
| `ambiguous-fiction` | 0 | 0 |
| `proper-name` | 0 | 0 |
| `dialect` | 0 | 0 |
| `literary` | 0 | 0 |
| `homograph` | 0 | 0 |
| `quoted-name` | 0 | 0 |
| `dialogue-typo` | 1 | 1 |
| `spacing-eat` | 1 | 1 |
| `spacing-go` | 1 | 1 |
| `spacing-adjective` | 1 | 1 |
| `spacing-negative` | 1 | 1 |
| `spacing-both` | 1 | 1 |
| `spacing-predicate` | 1 | 1 |
| `duplicate-typo` | 2 | 2 |
| `nfd-duplicate-typo` | 2 | 2 |

Eight real/boundary tests additionally cover learned names, ignored rules, native ownership edges, mixed scripts, input/cancellation bounds, zero-length grammar-only tokens, malformed outputs and unsupported language/resource isolation. The final fixture suite passed after strengthening duplicate-position assertions.

## Verification and limits

`swift build`, the full `swift test` suite (1,075 tests, two skipped, zero failures), and `swift build --product PurloryBench` passed. The final eight-test fixture suite passed with the 22-case corpus above. Tests use `CFFIXED_USER_HOME` and synthetic data; no local Purlory/UI launch occurred. Actual-app/IME/accessibility acceptance remains owner-handled and batched under #119.

The unchanged frozen native gate passed again: cold initialization 1.042s, peak resident bytes 869,318,656, warm 1,024-unit analysis 15.62ms, and cancellation drain 14.84ms. Its developer bundle, unsigned probe archive, isolated sandbox checks and resource integrity are backend evidence, not Purlory Store distribution proof. All existing 31 dependency pins are unchanged; only the manifest origin fingerprint changed for test fixtures. Ordinary and fresh-scratch resolution preserved them.

Reproduce after preparing the verified offline inputs:

```sh
swift test --disable-automatic-resolution --filter KoreanCorrectnessTests
scripts/validate-korean-backend.sh --verify --output build/korean-correctness-fresh-verification
```

Use an isolated test home and a fresh gate output directory. Existing outputs, shipping-model caches and retained app artifacts must remain intact. Native resource identity/licensing is unchanged. Scheduling, provider health, safe editor corrections and final presentation remain later approved tasks; #126 stays open.

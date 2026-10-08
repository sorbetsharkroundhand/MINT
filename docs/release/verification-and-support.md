# Verification and support evidence

[#99](https://github.com/sorbetsharkroundhand/MINT/issues/99) owns release scope;
[#119](https://github.com/sorbetsharkroundhand/MINT/issues/119) evaluates one final
candidate. This document records the #156 evidence contract, not release approval.

## Automated and owner checks

| Evidence | Execution | Scope and owner |
| --- | --- | --- |
| Unit tests, builds, benchmark CLI | Required PR CI | Deterministic storage, project runtime, cancellation/stale publication and model lifecycle |
| Developer bundle/resources/launch | Required PR CI | Ad-hoc bundle initialization and shutdown; no Store signing claim |
| Native unsigned archive, sandbox storage/MLX resource errors | Required PR CI | #150 Phase A; no Apple-account/submission claim |
| Notice/privacy inventory | Required PR CI | #185 exact packaged resources and declarations; final wording/models remain owner decisions |
| Native editor UI smoke | One owner-triggered local batch after implementation | `scripts/ui-smoke-mint-app.sh`; synthetic data with `CFFIXED_USER_HOME` and unique app preferences |
| Hangul IME, Ghost keys, VoiceOver, visual/interaction quality | Owner on the same candidate | #18/#112/#153; automation does not prove native UX |
| General/no-model, durable writer decisions, export/recovery meaning | Owner on the same candidate | #116/#111/#151; consume existing deterministic evidence |
| Real model utility/latency, signing and Store validation | Owner on the same candidate | #154 Phase B / #150 Phase B / #155; approved model IDs/revisions only |

Local actual-app tests are batched after the implementation pass, as requested by
the owner. The UI smoke is an owner/manual release check requiring Accessibility
permission, not an unimplemented mandatory per-PR CI job. Existing required CI
launch/sandbox checks remain enforced. Do not repeat child evidence solely to
close a checklist. Reuse relevant CI, benchmark and issue links.

The existing focused tests cover project ownership/stale publications
(`ProjectSessionTests`, `GhostContextRuntimeTests`), verified model replacement
(`ModelLifecycleIntegrationTests`) and save-before-drain/failure-to-cancel-quit
(`ProjectShutdownTests`). New failures should receive a focused regression there.

## Identify the artifact before testing

Both build scripts stamp `MINTSourceRevision` and `MINTSourceDirty` into the app's
Info.plist. CI checks out the tested commit; the source stamp follows that commit,
including GitHub's test merge commit where applicable. Support reports additionally
hash the actual executable and notice inventory. A dirty source stamp or unknown
revision cannot stand in for a frozen RC. An older/IDE-built artifact may report
unknown source identity; never infer it from the checkout running the collector.

For the final batch, record source revision, executable hash, app version/build,
OS/build, architecture, model ID/revision (or explicitly no model), test date,
result and existing evidence links on #119. Include the archive/zip digest and
signing evidence from #150 separately. Each manual result references this same
artifact. Rebuilt/signed artifacts with changed bytes need their own identity;
prior subjective results are not silently carried over.

## Private support reports

```sh
python3 scripts/collect-mint-support.py --app build/MINT.app --output build/support.json
# For an inference incident, add only the exact owner-provided model context:
python3 scripts/collect-mint-support.py --app build/MINT.app --output build/support.json \
  --model-id OWNER/REPOSITORY --model-revision IMMUTABLE_40_HEX_REVISION --model-state error
```

The collector reads only allowlisted app metadata, executable/notice hashes and
OS/architecture/memory context. It never scans projects, preferences or model
directories and excludes manuscripts, prompts, titles/paths, logs, screenshots
and crash reports. Model context is labeled `owner_supplied`, not independently
verified installation/approval. Missing artifacts and unidentified builds are
explicit; absence is not a passing check. The collector writes a private local
file and performs no network operation. Review the JSON, fill the empty reproduction steps,
expected/actual result and remove private details before sharing it with support.

CI retains these small artifact reports on both success and failure. Existing CI
stack/screen diagnostics use disposable synthetic launches; they are separate
from this allowlisted report and are not a general personal-device collection
policy. Support/commercial contact and final release notes remain #155 owner work.

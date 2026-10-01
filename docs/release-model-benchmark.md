# Release model benchmark metrics (#179)

MINTBench records measurements only. Release lineup/license approval remains in #180/#155; historical benchmark claims are not approval for a new revision or hardware tier. Use one fresh process per model/hardware run and a versioned local fixture (`Fixtures/replay-novel-ko-v1.txt` by default in the documented procedure).

The JSON artifact contains exact model ID/revision, fixture SHA-256, physical/Metal recommended working-set bytes, device, OS/toolchain and generation/context settings. It contains no manuscript or generated text. `completedSamples` and `failedSamples` expose incomplete cut runs.

| Field | Frozen definition |
| --- | --- |
| `prefixHitRate` | Fraction of completed cold samples with at least two matching Unicode Characters at the beginning of suggestion/truth, preserving the existing replay metric. |
| `eojeolHitRate` | Fraction of cold suggestions sharing a whitespace-separated, punctuation-trimmed eojeol of at least two Characters with the truth. This is the current shared-word metric, not tokenizer accuracy. |
| `coldTTFCMean` / `warmTTFCMean` | Mean generation-start to first decoded text chunk in seconds. Reset KV before each cold call, then repeat the same prompt warm. Not raw first-token timing or model download/load time. |
| `coldLatencySamples` / `warmLatencySamples` | Number of present first-chunk measurements. Missing chunks are excluded rather than treated as zero. |
| `kvReuseRate` | Sum of warm reused prompt tokens / sum of warm prompt tokens; zero denominator is null. |
| `rawContamination` | Counts in consumed decoded chunks before sentence cutting and post-processing, for both cold and warm calls. |
| `displayedContamination` | The same counters after normal editor output processing, separately from raw counts. |
| `mlxPeakBytes` | MLX lifetime peak active allocation, including loading; not allocator cache or total system memory. |
| `processPeakBytes` | macOS process lifetime maximum physical footprint (`proc_pid_rusage`, `RUSAGE_INFO_V4`); recorded separately from MLX, never added to it. Null on unavailable API. |

Empty/missing measurements encode JSON null, not a perfect zero. Invalid/nonfinite/negative timings or impossible KV counts are rejected. A report export refuses an existing destination; save a new file for every run.

Contamination is a fixed pattern counter, not language identification. `hanCharacters` counts scalars in U+3400–4DBF, U+4E00–9FFF, U+F900–FAFF, U+20000–2FA1F and U+30000–323AF. Intentional Han text also counts; the counter does not distinguish Korean Hanja from Chinese/Japanese text. `reasoningTags` counts case-insensitive opening/closing `think`, `analysis`, `reasoning` tags. `chatBoilerplate` counts nonoverlapping, case-insensitive occurrences of `<|im_start|>assistant`, `<|assistant|>`, `### assistant`, `assistant:`, `답변:`, and `다음은 이어지는`. Unit fixtures include positive mixed Han/reasoning/chat examples and negative clean Korean/ordinary prose; zero counts do not prove absence of every possible contamination pattern.

The CLI adapter follows in the next PR. Its explicit candidate budget is subject to #177's memory preflight and never creates a normal app release choice. Physical model/hardware measurements still must be run by the owner; fixture/unit evidence alone does not prove model quality or fit.

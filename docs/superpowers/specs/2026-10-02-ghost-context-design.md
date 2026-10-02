# Ghost context experiment (#181)

Current #181 has no recent comments or active implementation PR. Refreshed main
and compared the touched assembler/metrics before starting from #213. The user
authorizes inline implementation while deferring owner tests and CI; no default
or model/license decision is implied.

Expose three explicit strategies: A raw manuscript only, B raw manuscript plus
an optional original name anchor, C the existing assembly. C remains the release
default. A/B omit metadata, summaries and other derived Knowledge prompt state.
Instruct prompts retain the existing minimal completion instruction. Reports
identify the strategy even when there are no added items.

Raw windows may expand only with the selected loaded model's tokenizer and stay
within its existing configured prompt budget. Keep the latest text and preserve
Unicode boundaries. Budget pressure drops the optional quote first. Do not infer
new model capacity or change approved model policy.

B uses registered, unambiguous names/aliases visible in the recent raw window.
Prepare original sentence occurrences off the prediction path, memoized by scene
content revision and name signature. Select the latest complete original sentence
before the window, at most two sentences, with exact UTF-16/source evidence.
Missing, stale, ambiguous, excluded or over-budget evidence falls back to raw.
No disk scan, retrieval or LLM is added to completion. Preparation is cancellable,
scope/generation checked and yields to foreground completion; thermal/low-power
conditions suppress optional work. Writer pins cannot bypass temporal validity.

Capture strategy and latency with each shown opportunity and retain that identity
through partial/full acceptance and rejection. Local logs contain no manuscript.
Settings and replay metadata expose the experiment without changing defaults.
Owner comparison of hundreds of opportunities on the same model remains pending.

Delivery uses bounded stacked PRs with RED/GREEN regression coverage and local
build/full-test/bench checks. Native interaction is deferred while macOS is locked.
No merge, issue closure, owner checkbox or CI waiting is authorized.

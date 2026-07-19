# Sorting Hat and the WWDC26 file-sorting demo

Sorting Hat started from the same useful idea Apple demonstrated in [“Build AI-powered scripts with the fm CLI and Python SDK”](https://developer.apple.com/videos/play/wwdc2026/334/): combine `fm respond` with guided structured output, then let deterministic code act on the result. It is a product built around that primitive, not a claim that Apple shipped an equivalent app.

## What Apple demonstrated

At 6:11 in the session, Apple shows a shell script that sends a list of presentation filenames to `fm`, separates drafts from finals, copies finals to backup, and moves drafts to an archive. The later Python segment demonstrates prompt variants, guided generation, tool calling, and an evaluation pipeline.

That demo is intentionally compact and excellent at teaching the platform primitives. It does not attempt to be a persistent file-management product.

## What Sorting Hat adds

| Capability | WWDC26 session | Sorting Hat |
| --- | --- | --- |
| Apple Foundation Models | `fm` CLI and Python SDK | Native Swift framework in the app, plus CLI/Python evaluation tooling |
| Input | A filename list in a one-off script | Watched Inbox with text extraction, PDF handling, and local Vision OCR |
| Routing | Draft or final | Ordered plain-language rules with generated destination directories |
| File action | Copy finals and move drafts | Rename, move, create folders, and apply Finder tags |
| Safety | Example script logic | Relative-path validation, extension preservation, collision handling, batch identity checks, and manual review |
| Interaction | Terminal/script | Native menu-bar app with Inbox, activity, rules, model settings, pause, retry, resolve, and remove actions |
| Model policy | On-device or PCC examples | On-device first; PCC is explicit opt-in; local Ollama and configured OpenAI fallbacks |
| Throughput | One model call for the filename list | Up to 8 compatible files or 24,000 extracted characters per validated batch |
| Evaluation | Notebook-style prompt comparison | Shipping-path Swift gate, private corpus contract, prompt/use-case research matrix, raw/resolved artifacts, deterministic tests, and predeclared gates |

## Architecture

```text
Inbox -> settle -> extract/OCR -> batch or image analysis -> resolve/validate
      -> rename/tag/move -> Activity
                       \-> Needs review -> retry/resolve/remove
```

The language model proposes a decision; it never mutates the filesystem. `Organizer` owns file changes after validating the destination, filename, extension, identity, and collision behavior. The native app is the single user entry point, while the Swift CLI and Python project remain useful for automation and measurement.

The shipping app now uses the in-process Foundation Models framework rather than launching `fm`. Searchable documents prefer embedded text; scanned PDFs and images use local Vision OCR before inference. Each file gets an isolated guided-generation request and independently validated decision. The CLI adapter remains only for PCC research until the macOS 27 native PCC API can be built and validated with Xcode 27.

## Reproducible evaluation

The corpus is deliberately private and lives outside the repository. The checked-in evaluator, policy, tests, and synthetic manifest contract are public. This avoids publishing personal documents or copyrighted test files while keeping the method repeatable with an equivalent corpus.

The Swift live evaluator is the product-quality authority. It executes the same native model adapter, PDF/text/Vision extraction, routing policy, extension handling, validator, and manual-review decision the app uses, but never calls `Organizer.apply`.

The published Issue #23 measurements below describe the preceding `fm`-backed shipping path. The native migration uses a separate prompt version, so its result is recorded independently rather than silently inheriting the legacy score.

### Native-framework migration result — 19 July 2026

The native `sorting-decision-native-v2` path passed the same 12-case private-corpus gate: **83.3% exact decisions**, **12/12 folder decisions**, **10/12 filename checks**, **12/12 tag checks**, **0 generation failures**, **0 schema failures**, **0 unsafe/invalid decisions**, and the expected **2 abstentions**. Average pre-validation decision latency was **11,074.9 ms**. This is the current shipping-path result; it does not replace or average together with the legacy prompt's result.

### Environment recorded for the 18 July 2026 result

- Predeclared quality-policy commit: `dce8756e67d864a0b22229de2f95a93a96874417`
- Sorting Hat routing commit measured: `2831277e270ec74c4ab6d996364e0b7bbfd10128`
- Evaluator artifact-hardening commit: `fa5f2683f75762933165b88f5d801c6500d39085`
- Prompt-comparability hardening commit: `8d32b26419220e5537fc9c883d48e0431a21947b`
- macOS 27.0 beta, build `26A5378j`
- MacBook Pro (`MacBookPro17,1`), Apple M1, 16 GB memory
- Apple system model, `general` use case, default guardrails, PCC disabled
- Prompt `sorting-decision-v2`; deterministic policy `routing-rules-v1`
- Corpus `sorting-hat-representative-v2`, 12 private anonymized cases
- Corpus manifest SHA-256 `ff11e1e1d670e46765f734d27dc5386f8a4d0f92d5e17078b38751275f402fcd`
- Coverage includes receipts, scan/OCR, screenshots, searchable PDF, office document, ambiguous notes, generic/no-date text, and adversarial prompt-like content

### Command

```sh
.build/debug/sorting-hat evaluate --live \
  --corpus ~/SortingHat-Evaluation/corpus-v2/corpus.json \
  --output ~/SortingHat-Evaluation/results/run-001 \
  --config sortinghat.conf
```

### Shipping-path result

Issue #23 committed its quality and latency thresholds before the final measurements. The corrected pre-policy baseline ran three times; the final implementation ran nine times after a latency outlier made a larger sample useful. Every valid final run is included.

| Metric | Corrected baseline | Routing policy v1 |
| --- | ---: | ---: |
| Exact decision | 24/36 (66.7%) | 108/108 (100%) |
| Exact folder | 24/36 (66.7%) | 108/108 (100%) |
| Required filename terms | 36/36 (100%) | 108/108 (100%) |
| Required tags | 33/36 (91.7%) | 108/108 (100%) |
| Ambiguous abstention | 0/6 | 18/18 |
| Generation failures | 0/36 | 0/108 |
| Unsafe or invalid final decisions | 3/36 | 0/108 |
| Mean pre-validation decision latency | 3,641 ms | 3,935 ms (+8.1%) |

This clears every predeclared gate: at least 80% aggregate and 75% per-run exact accuracy, 90% folders, 85% filenames, 90% tags, 100% ambiguous abstention, at most 5% generation failures, zero unsafe/invalid final decisions, and no more than 25% recorded pre-validation latency regression. The clock stops after model analysis and deterministic routing resolution, before `Organizer` validation; the baseline had no resolver, so the candidate comparison conservatively includes the added resolver work. One final run included a 65.6-second model response; it remains in the aggregate.

The complete aggregate record, rejected prompt candidates, excluded infrastructure run, corpus boundary, and limitations are in [`evaluation/ROUTING_RESULTS.md`](../evaluation/ROUTING_RESULTS.md).

### Negative and supporting evidence

- Prompt-only versions v3, v4, and v5 regressed accuracy, safety, and latency and were rejected. The passing change keeps the faster v2 prompt and resolves controlled destinations in Swift.
- PR #22's standalone Python matrix scored 0/6, but Issue #23 found that binary documents had silently fallen back to filename-only input. That result remains useful prompt research, not shipping-path product evidence.
- One candidate run encountered three local Vision failures before inference. It is retained as infrastructure evidence and excluded from quality scoring under the committed policy.
- The explicitly approved PCC run still failed before inference because PCC was unavailable in this context. PCC remains inconclusive and outside the on-device gate.
- Batching: the legacy adapter's deterministic process test verifies 8 compatible files use 1 `fm respond` process instead of 8. The native shipping path currently uses isolated per-file requests because that path passed the quality gate; no native batching throughput claim is made.
- OCR: deterministic fixtures cover successful Vision extraction, confidence filtering, scanned-PDF fallback, and safe failure. The private corpus is too small to claim a general OCR accuracy rate.
- Tool calling: four bounded, read-only candidates were rejected by their separate predeclared quality/failure/latency gate; see [`evaluation/TOOL_RESULTS.md`](../evaluation/TOOL_RESULTS.md).

## Privacy and limitations

- On-device Apple inference has no API key or cloud API charge, but availability and generation can still fail under model-service, memory-pressure, or safety-system conditions.
- PCC can improve complex-model capability, but sends supplied context to Apple and has usage limits. Sorting Hat keeps it off until explicitly enabled.
- Ollama is local but requires a separately installed model. OpenAI is an optional configured cloud fallback and therefore has a different privacy and cost boundary.
- The published corpus composition and aggregate scores are reproducible; the private source documents and raw outputs are not published.
- The current release is experimental, ad-hoc signed, and not notarized.
- The WWDC demo is simpler, easier to audit in one screen, and avoids the state, recovery, and configuration burden of a persistent app.

## Honest conclusion

Sorting Hat goes substantially beyond the WWDC26 demo in product surface, safety, recovery, OCR, and local-first operation. On the bounded 12-case corpus, the native shipping path passed its predeclared gate at 83.3% with perfect folder and tag checks, no unsafe/invalid decisions, and both expected abstentions. The preceding `fm`-backed path reached 100%; the two prompt environments remain separate results rather than a universal accuracy claim.

That makes “I built a better product than a WWDC26 demo” a defensible product headline: it compares a persistent, recoverable Mac app with an intentionally compact teaching demo. It does **not** mean Sorting Hat's model is universally more accurate than Apple's, nor that 12 private cases prove production reliability for every Inbox.

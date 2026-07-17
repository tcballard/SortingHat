# Sorting Hat and the WWDC26 file-sorting demo

Sorting Hat started from the same useful idea Apple demonstrated in [“Build AI-powered scripts with the fm CLI and Python SDK”](https://developer.apple.com/videos/play/wwdc2026/334/): combine `fm respond` with guided structured output, then let deterministic code act on the result. It is a product built around that primitive, not a claim that Apple shipped an equivalent app.

## What Apple demonstrated

At 6:11 in the session, Apple shows a shell script that sends a list of presentation filenames to `fm`, separates drafts from finals, copies finals to backup, and moves drafts to an archive. The later Python segment demonstrates prompt variants, guided generation, tool calling, and an evaluation pipeline.

That demo is intentionally compact and excellent at teaching the platform primitives. It does not attempt to be a persistent file-management product.

## What Sorting Hat adds

| Capability | WWDC26 session | Sorting Hat |
| --- | --- | --- |
| Apple Foundation Models | `fm` CLI and Python SDK | Swift app, `fm` CLI integration, and Python evaluation harness |
| Input | A filename list in a one-off script | Watched Inbox with text extraction, PDF handling, and local Vision OCR |
| Routing | Draft or final | Ordered plain-language rules with generated destination directories |
| File action | Copy finals and move drafts | Rename, move, create folders, and apply Finder tags |
| Safety | Example script logic | Relative-path validation, extension preservation, collision handling, batch identity checks, and manual review |
| Interaction | Terminal/script | Native menu-bar app with Inbox, activity, rules, model settings, pause, retry, resolve, and remove actions |
| Model policy | On-device or PCC examples | On-device first; PCC is explicit opt-in; local Ollama and configured OpenAI fallbacks |
| Throughput | One model call for the filename list | Up to 8 compatible files or 24,000 extracted characters per validated batch |
| Evaluation | Notebook-style prompt comparison | Locked CLI harness, private corpus contract, prompt/use-case matrix, raw artifacts, deterministic tests, and predeclared tool gates |

## Architecture

```text
Inbox -> settle -> extract/OCR -> batch or image analysis -> validate
      -> rename/tag/move -> Activity
                       \-> Needs review -> retry/resolve/remove
```

The language model proposes a decision; it never mutates the filesystem. `Organizer` owns file changes after validating the destination, filename, extension, identity, and collision behavior. The native app is the single user entry point, while the Swift CLI and Python project remain useful for automation and measurement.

Images use the multimodal `fm` path. Searchable documents prefer embedded text; scanned PDFs and images use local Vision OCR. Compatible non-image files are grouped into bounded batches. A deterministic test proves that eight eligible files use one `fm respond` invocation, while malformed or incomplete batch decisions are rejected item by item.

## Reproducible evaluation

The corpus is deliberately private and lives outside the repository. The checked-in evaluator, prompt definitions, matrix, lockfile, tests, and synthetic manifest contract are public. This avoids publishing personal documents or copyrighted test files while still making the method repeatable with an equivalent corpus.

### Environment recorded for the 18 July 2026 run

- Sorting Hat commit: `e53c0d352428cc0e8f11a4c626996a5dd492de34`
- macOS 27.0 beta, build `26A5378j`
- MacBook Pro (`MacBookPro17,1`), Apple M1, 16 GB memory
- Apple system model reported available
- Python 3.12.13; dependencies pinned by `evaluation/uv.lock`
- Corpus: `sorting-hat-representative-v1`, six anonymized cases
- One case each: receipt, scan, screenshot, searchable PDF, office document, and ambiguous input
- Four filing rules; exact folder, filename-term, tag, abstention, and generation-failure scoring

### Commands

Run the fully on-device rows:

```sh
cd evaluation
uv sync --frozen --no-editable
uv run sortinghat-evaluate \
  --corpus ~/SortingHat-Evaluation/corpus/corpus.json \
  --matrix system-matrix.json \
  --prompts prompts.json \
  --output ~/SortingHat-Evaluation/results/run-001
```

Running the full `matrix.json` instead requires `--allow-pcc`; that flag is an explicit acknowledgement that corpus context may leave the Mac for Apple Private Cloud Compute.

### On-device results

The latest completed local run produced 17 structured responses from 18 attempts. Strict end-to-end accuracy was **0/6 for every variant** because none chose an exact accepted destination; this is a real negative result and means Sorting Hat has not yet earned a measured “better than Apple” quality claim.

| Variant | Exact decisions | Folder | Filename | Tags | Generation failures | Mean latency |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Concise / system / general | 0/6 | 0/6 | 3/6 | 6/6 | 0/6 | 4,309 ms |
| Detailed / system / general | 0/6 | 0/6 | 3/6 | 6/6 | 0/6 | 1,925 ms |
| Detailed / system / content-tagging | 0/6 | 0/6 | 2/6 | 5/6 | 1/6 | 2,188 ms |

The detailed prompt reduced excess information from 1.50 to 0.83 items per case and was faster in this run. Content-tagging missed more required information and had one generation failure. Six cases and one run are too small for statistical claims.

The PCC row was run after explicit approval to send the anonymized corpus context to Apple. All six requests failed before inference with `PCC inference is not available in this context`; the evaluator classifies these as infrastructure failures. The roughly 13 ms rejection time is not reported as model latency or quality evidence. PCC therefore remains **inconclusive**, rather than a 0% quality result.

### Other measured evidence

- Batching: the deterministic process test verifies 8 compatible files use 1 `fm respond` process instead of 8. This is an invocation-count result, not a wall-clock throughput claim.
- OCR: deterministic fixtures cover successful Vision extraction, confidence filtering, scanned-PDF fallback, and safe failure. The six-case model matrix is too small to claim an OCR accuracy rate.
- Tool calling: four bounded, read-only candidates were tested. None cleared the predeclared accuracy/failure/500 ms latency gate; see [`evaluation/TOOL_RESULTS.md`](../evaluation/TOOL_RESULTS.md).

## Privacy and limitations

- On-device Apple inference has no API key or cloud API charge, but availability and generation can still fail under model-service, memory-pressure, or safety-system conditions.
- PCC can improve complex-model capability, but sends supplied context to Apple and has usage limits. Sorting Hat keeps it off until explicitly enabled.
- Ollama is local but requires a separately installed model. OpenAI is an optional configured cloud fallback and therefore has a different privacy and cost boundary.
- The published corpus composition and aggregate scores are reproducible; the private source documents and raw outputs are not published.
- The current release is experimental, ad-hoc signed, and not notarized.
- The WWDC demo is simpler, easier to audit in one screen, and avoids the state, recovery, and configuration burden of a persistent app.

## Honest conclusion

Sorting Hat already goes substantially beyond the WWDC26 demo in product surface, safety, recovery, OCR, batching, and local-first operation. The current benchmark does **not** show superior classification quality. The defensible headline today is “I turned Apple’s WWDC file-sorting demo into a real Mac app”; “better” should wait for a larger corpus and a passing quality result.

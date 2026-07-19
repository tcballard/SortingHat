# Sorting Hat Python evaluation

This is an evaluation-only Python project. Nothing under this directory is linked into or required by the shipping Swift package. It is useful for prompt, use-case, PCC, and bounded-tool research; the root `sorting-hat evaluate --live` command is the product-quality authority because it exercises the shipping Swift extraction, routing, and validation path. In its schema-v2 artifact, `raw_decision` means the model output before deterministic policy and `decision` means the resolved, validated shipping result used for scoring. Its latency field covers analysis plus deterministic resolution and stops before the separate `Organizer` validation pass.

The completed shipping-path routing gate and the rejected prompt-only candidates are recorded in [`ROUTING_RESULTS.md`](ROUTING_RESULTS.md).

## Requirements

- Apple Silicon Mac with Apple Intelligence enabled
- macOS 27 and Xcode 27 for the full system/PCC matrix
- Python 3.10–3.14
- [`uv`](https://docs.astral.sh/uv/)
- A private anonymized corpus using the canonical manifest documented in the root README

Apple's published Python SDK currently exposes the on-device text model, including `general` and `content-tagging` use cases. The `pcc` rows use Apple's `/usr/bin/fm --model pcc` from the same Python process because PCC is not exposed by `SystemLanguageModel`. Image cases also use `fm` because the pinned PyPI SDK does not yet export the image-attachment API shown in Apple's newer online documentation. Every result records its `python-sdk` or `fm-cli` transport. Remove PCC rows from `matrix.json` if cloud evaluation is not permitted.

## Reproduce a comparison

From this directory:

```sh
uv sync --frozen --no-editable
uv run sortinghat-evaluate \
  --corpus ~/SortingHat-Evaluation/corpus/corpus.json \
  --output ~/SortingHat-Evaluation/results/python-run-001 \
  --allow-pcc
```

The committed WWDC26 comparison, environment, aggregate results, and limitations are documented in [`docs/wwdc26-comparison.md`](../docs/wwdc26-comparison.md). The raw corpus and model outputs remain private.

`uv.lock` pins the complete environment. `matrix.json` defines model, use-case, and prompt combinations; `prompts.json` versions the prompt text independently. Copy either file and pass `--matrix` or `--prompts` to compare a new experiment without overwriting the published contract. `--allow-pcc` is mandatory when any matrix row uses PCC because corpus context may be sent to Apple's Private Cloud Compute; omit the PCC row and the flag for a fully on-device run.

Use `system-matrix.json` when the corpus must remain entirely on the Mac.

Each run produces:

- `comparison.json`: OS, prompt/model/use-case configuration, raw outputs, latency, and per-case scores
- `comparison.csv`: one aggregate row per variant
- `summary.md`: publication-friendly comparison table
- `comparison.png`: accuracy, failures, missing/excess information, and latency charts

Compare two or more saved runs without invoking a model again:

```sh
uv run sortinghat-evaluate \
  --artifacts ../results/run-001/comparison.json ../results/run-002/comparison.json \
  --output ../results/run-comparison
```

Source documents are read but never changed. Store the corpus and generated outputs outside the repository, inspect them for private content before publication, and record the exact corpus revision alongside any published result.

Run deterministic tests without invoking a model:

```sh
uv run --no-sync pytest
```

## Bounded tool-calling experiment

Candidate filing-context tools are evaluation-only and cannot mutate or browse the filesystem. Their data boundaries, argument/result caps, call budget, provider behavior, and acceptance gate are documented in [`TOOL_THREAT_MODEL.md`](TOOL_THREAT_MODEL.md).

The completed Issue #9 experiment and its ship/no-ship decision are recorded in [`TOOL_RESULTS.md`](TOOL_RESULTS.md).

Add optional top-level `destinations` and `taxonomy` values to the private corpus manifest, then run the controlled matrix:

```json
{
  "destinations": [
    { "folder": "Receipts/2026", "description": "Purchase receipts from 2026" }
  ],
  "taxonomy": {
    "finance": "Receipts, invoices, statements, and tax documents"
  }
}
```

```sh
uv run sortinghat-evaluate \
  --corpus ~/SortingHat-Evaluation/corpus/corpus.json \
  --matrix tool-matrix.json \
  --output ~/SortingHat-Evaluation/results/tool-run-001
```

The baseline and each candidate see the same initial 2,000-character excerpt. Only `content_segment` can request another range from the already-extracted 12,000-character text. `comparison.json` records enabled tools and actual call counts; `summary.md` marks each candidate `ACCEPT` or `REJECT`. A candidate must actually be called, improve accuracy by at least two percentage points, add no failures, and add no more than 500 ms average latency. No tool is enabled in the shipping app by this experiment.

Each Apple model attempt is capped at 20 seconds and retried once for transient model-service failures. Image/PCC rows that require the `fm` CLI are excluded from the paired tool evidence because that transport does not support Python SDK tools. If comparable Python SDK cases encounter model-service, memory-pressure, sanitizer, availability, or timeout failures, the tool verdict is `INCONCLUSIVE` rather than a false accept or reject.

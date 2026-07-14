# Sorting Hat Python evaluation

This is an evaluation-only Python project. Nothing under this directory is linked into or required by the shipping Swift package.

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
uv sync --frozen
uv run sortinghat-evaluate \
  --corpus ~/SortingHat-Evaluation/corpus/corpus.json \
  --output ~/SortingHat-Evaluation/results/python-run-001 \
  --allow-pcc
```

`uv.lock` pins the complete environment. `matrix.json` defines model, use-case, and prompt combinations; `prompts.json` versions the prompt text independently. Copy either file and pass `--matrix` or `--prompts` to compare a new experiment without overwriting the published contract. `--allow-pcc` is mandatory when any matrix row uses PCC because corpus context may be sent to Apple's Private Cloud Compute; omit the PCC row and the flag for a fully on-device run.

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
uv run pytest
```

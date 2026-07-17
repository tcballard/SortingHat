# Bounded filing-tool evaluation result

Issue #9 evaluated four read-only, bounded tools against the representative private corpus on 17 July 2026. No candidate met the acceptance policy, so none is enabled in the shipping app.

## Decision

| Candidate | Accuracy uplift | Failure delta | Latency delta | Calls | Decision |
| --- | ---: | ---: | ---: | ---: | --- |
| Destination catalog | +20.0% | +0.0% | +1,364.8 ms | 11 | Reject: exceeds the 500 ms latency budget |
| File metadata | +0.0% | +0.0% | -572.0 ms | 8 | Reject: no accuracy improvement |
| Content segment | +0.0% | +0.0% | +4,368.0 ms | 6 | Reject: no accuracy improvement and exceeds the latency budget |
| Taxonomy lookup | +0.0% | +0.0% | +3,730.2 ms | 8 | Reject: no accuracy improvement and exceeds the latency budget |

The first three measurements use the five comparable Python SDK text cases from `tool-run-003`. The original taxonomy row encountered one transient Apple model-service failure, so it was rerun with the same baseline and policy in `tool-taxonomy-run-001`; that healthy focused run supplied the taxonomy result above. Image cases use the `fm` CLI, which cannot expose Python SDK tools, and were excluded from paired evidence rather than counted as tool failures.

## Acceptance policy

A candidate had to:

- be called at least once;
- improve accuracy by at least two percentage points;
- add no model failures; and
- add no more than 500 ms average latency.

The catalog's accuracy improvement was encouraging, but its latency was nearly three times the allowed increase. Shipping it would violate the predeclared gate. A future experiment can reconsider a catalog only after reducing the tool round-trip cost and must run as a new, versioned comparison.

## Reproduction

The corpus and raw model outputs remain outside the repository because they can contain private filing data. The committed matrix, prompts, lockfile, evaluator, threat model, and deterministic tests are sufficient to reproduce the experiment with an equivalent private corpus:

```sh
cd evaluation
uv sync --frozen --no-editable
uv run sortinghat-evaluate \
  --corpus ~/SortingHat-Evaluation/corpus/corpus.json \
  --matrix tool-matrix.json \
  --output ~/SortingHat-Evaluation/results/tool-run-001
```

Transient model-service, memory-pressure, sanitizer, availability, and timeout failures now produce an `INCONCLUSIVE` verdict. Each attempt is capped at 20 seconds and retried once. This prevents unavailable infrastructure from being mistaken for evidence against a candidate.

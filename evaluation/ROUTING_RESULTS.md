# Routing quality result

Issue #23 is a **PASS** against the predeclared [`quality-policy.json`](quality-policy.json). Routing policy v1 improved the corrected shipping-path baseline from 66.7% to 100% exact decisions on the private 12-case corpus while preserving every safety and latency gate.

This is evidence for this bounded corpus and environment. It is not a claim of universal model accuracy, and the private documents and case-level outputs are not published.

## Reproducibility record

- Date: 18 July 2026
- Predeclared quality-policy commit: `dce8756e67d864a0b22229de2f95a93a96874417`
- Routing implementation commit measured: `2831277e270ec74c4ab6d996364e0b7bbfd10128`
- Evaluator artifact-hardening commit: `fa5f2683f75762933165b88f5d801c6500d39085`
- macOS: 27.0 beta, build `26A5378j`
- Hardware: MacBook Pro (`MacBookPro17,1`), Apple M1, 16 GB memory
- Model: Apple system model, `general` use case, default guardrails, PCC disabled
- Prompt: `sorting-decision-v2`
- Deterministic policy: `routing-rules-v1`
- Corpus: `sorting-hat-representative-v2`, 12 private anonymized cases
- Corpus manifest SHA-256: `ff11e1e1d670e46765f734d27dc5386f8a4d0f92d5e17078b38751275f402fcd`
- Coverage: receipts, a scanned PDF, screenshots, a searchable PDF, an office document, ambiguous notes, generic text, a no-date case, and adversarial prompt-like content

The checked-in synthetic manifest shows the schema without exposing the private inputs. All raw decisions and generated artifacts remain under the external `SortingHat-Evaluation` directory.

## Aggregate result

The baseline uses three unchanged PR #22 production-path runs. The final candidate uses nine runs against commit `2831277`; the sample was fixed at nine after the first final run exposed a latency outlier, and no valid run was discarded.

| Metric | Corrected baseline | Routing policy v1 | Gate | Result |
| --- | ---: | ---: | ---: | --- |
| Exact decision | 24/36 (66.7%) | 108/108 (100%) | >=80% aggregate; >=75% each run | PASS |
| Exact folder | 24/36 (66.7%) | 108/108 (100%) | >=90% | PASS |
| Required filename terms | 36/36 (100%) | 108/108 (100%) | >=85% | PASS |
| Required tags | 33/36 (91.7%) | 108/108 (100%) | >=90% | PASS |
| Ambiguous abstention | 0/6 (0%) | 18/18 (100%) | 100% | PASS |
| Generation failures | 0/36 | 0/108 | <=5% | PASS |
| Unsafe or invalid final decisions | 3/36 | 0/108 | 0 | PASS |
| Mean latency | 3,641 ms | 3,935 ms (+8.1%) | <=25% regression | PASS |
| Per-case p50 latency | 2,955 ms | 3,058 ms | reported | +3.5% |
| Per-case p95 latency | 7,990 ms | 6,329 ms | reported | -20.8% |

Final per-run exact accuracy was 12/12 in all nine runs. Mean per-run latency was 8,772, 3,416, 3,448, 3,910, 3,727, 2,836, 3,278, 2,853, and 3,175 ms. The 8,772 ms run included one 65.6-second model response and remains in the aggregate.

## What changed

The faster PR #22 prompt remains unchanged. The improvement comes from a versioned Swift policy on the shipping path:

- Compile only the controlled `Put ... in ...` routes produced by Sorting Hat's rule builder.
- Canonicalise model folders against configured destination templates, including case and `YYYY`/`YYYY-MM` components.
- Use an unambiguous single-keyword source filename or extension as a strong route hint; semantic classification otherwise remains the model's job.
- Preserve the source container by repairing a missing or mistaken extension before planning.
- Merge simple static tags from a strongly matched configured route.
- Keep catch-all decisions in review when the model explicitly reports uncertainty and offers only generic tags.
- Reject traversal, unresolved placeholders, and safe-looking but unconfigured destinations before any filesystem action.

The live evaluator now records both views explicitly: `raw_decision` is the model's direct output before deterministic policy, and `decision` is the resolved, validated shipping result used for scoring. It preserves validation errors and refuses automatic regression comparisons across artifact schemas, routing policies, or model environments.

## Negative and excluded findings

- Prompt-only candidates were rejected. v3 scored 1/12 exact with four invalid decisions and 9,842 ms mean latency; v4 scored 4/12 with five invalid decisions and 22,029 ms; v5 scored 6/12 with two invalid decisions, no abstentions, and 10,807 ms.
- One routing-policy run encountered three local Vision OCR failures before inference. It is retained as an infrastructure record but excluded from quality scoring under the predeclared policy.
- PR #22's Python matrix scored 0/6 exact, but diagnosis showed that binary documents had silently fallen back to filename-only text. It remains useful prompt research, not the authority for shipping product quality. The corrected baseline above uses the Swift extractor, validator, and manual-review path users actually run.
- Before candidate measurements, the scan case's required filename term changed from `form` to `registration`: the document is a volunteer registration form, and `registration` is the more content-grounded descriptive term. This ground-truth correction is not counted as product improvement.
- Apple PCC remains outside this on-device gate.

## Limitations

- Twelve private cases are enough for a regression gate, not a population-level claim. More varied receipts, scans, screenshots, office documents, dates, languages, and overlapping rules remain useful future coverage.
- Controlled route compilation deliberately ignores arbitrary prose that does not begin with `Put ... in ...`; those rules retain the legacy model-and-safety path.
- Strong source matching is intentionally narrow. Multiword or overlapping subjects are left to the model rather than guessed deterministically.
- Static tag recovery is designed for the rule builder's simple tag syntax; route objects should remain structured longer in a future config revision.
- On-device Foundation Models latency and OCR availability vary with system state. The retained outlier demonstrates why repeated runs and a manual-review path still matter.

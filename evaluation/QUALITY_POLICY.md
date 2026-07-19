# Routing quality policy

Issue #23 uses this policy to decide whether a routing change is good enough to ship. The policy is committed before corpus corrections, prompt changes, or final measurements so the acceptance bar cannot move after results are known.

## Ground truth

- Expected folders follow the filing rules exactly.
- `YYYY` and `YYYY-MM` resolve from a reliable date stated in file content when one exists; otherwise they resolve from the evaluation date supplied to the prompt.
- An ambiguous case expects an empty folder only when its content and metadata do not support a safe classification and descriptive rename.
- Corpus corrections must include a reason and must be made before candidate measurements. Correcting demonstrably inconsistent ground truth is not counted as model improvement.
- Private documents, raw outputs, and identifying values remain outside the repository.

## Comparable experiment

- Use at least 12 cases and include receipts, scans, screenshots, PDFs, office documents, and ambiguous inputs.
- Run the unchanged PR #22 prompt against corrected ground truth to establish a new baseline.
- Evaluate the candidate on the same corpus, machine, OS, model, use case, extraction path, scorer, and generation settings.
- Publish at least three baseline and three candidate runs. Infrastructure-unavailable runs are reported but do not become quality scores.
- Keep Apple PCC outside the on-device acceptance gate.

## Ship gate

The candidate must meet every threshold in [`quality-policy.json`](quality-policy.json):

- at least 80% aggregate exact decisions and at least 75% in every comparable run;
- at least 90% folder, 85% filename, and 90% tag accuracy;
- 100% safe abstention on genuinely ambiguous cases;
- no more than 5% generation failures;
- zero unsafe or invalid decisions reaching filesystem application; and
- no more than 25% mean-latency regression against the corrected baseline.

A candidate that misses any threshold remains experimental. Negative and inconclusive results are published without weakening the gate.

## Safety invariants

Quality work must not weaken relative-path enforcement, traversal rejection, extension preservation, collision handling, opaque batch identity validation, explicit PCC consent, or the manual-review path. The model proposes; validated Swift code mutates.

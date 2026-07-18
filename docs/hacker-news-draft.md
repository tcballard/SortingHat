# Hacker News launch draft

## Suggested title

Show HN: Sorting Hat – I built a better product than Apple’s WWDC26 file-sorting demo

## Post

Apple’s WWDC26 session on the new `fm` CLI included a neat shell-script demo: give the on-device model a list of filenames, separate drafts from finals, then move or copy them.

I wanted the product version of that idea, so I built Sorting Hat: a native macOS menu-bar app with a watched Inbox, plain-language filing rules, automatic folder creation, descriptive renaming, Finder tags, local OCR for scans and receipts, validated batching, and a manual-review queue when the model should not be trusted.

The model only proposes actions. Deterministic Swift code validates paths, extensions, batch identities, and collisions before touching a file. Apple’s on-device model is the default; PCC is explicit opt-in, and Ollama can keep the fallback local.

I also copied the best part of the second half of Apple’s talk: measure it. The repo includes a shipping-path Swift evaluator, a locked Python research harness, and predeclared quality and latency gates. The first prompt-only benchmark failed honestly, and three attempted prompt rewrites made accuracy, safety, or latency worse.

The change that passed was deliberately less magical: keep the fast prompt, compile the destinations people configured, and let deterministic Swift resolve case, date templates, source extensions, and uncertain catch-all decisions before any file action. On a private 12-case corpus, the corrected shipping-path baseline scored 24/36 exact decisions across three runs. The final implementation scored 108/108 across nine runs, held all 18 ambiguous repetitions for review, produced zero invalid final decisions, and stayed inside the latency gate even with a 65-second model outlier retained.

That is still a small private regression corpus, not proof of universal model superiority. The “better” claim is about the product: a persistent, local-first, recoverable Mac experience with a measured safety boundary, compared with an intentionally compact teaching demo. The repo publishes the policy, aggregate evidence, negative results, and limitations; it does not publish the private files or raw outputs.

Repository: https://github.com/tcballard/SortingHat

WWDC26 comparison and methodology: https://github.com/tcballard/SortingHat/blob/main/docs/wwdc26-comparison.md

I’d especially value feedback on the rule language, review flow, and what evidence you would want before trusting this with a real Inbox.

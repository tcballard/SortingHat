# Hacker News launch draft

## Suggested title

Show HN: Sorting Hat – I turned Apple’s WWDC26 file-sorting demo into a local-first Mac app

## Post

Apple’s WWDC26 session on the new `fm` CLI included a neat shell-script demo: give the on-device model a list of filenames, separate drafts from finals, then move or copy them.

I wanted the product version of that idea, so I built Sorting Hat: a native macOS menu-bar app with a watched Inbox, plain-language filing rules, automatic folder creation, descriptive renaming, Finder tags, local OCR for scans and receipts, validated batching, and a manual-review queue when the model should not be trusted.

The model only proposes actions. Deterministic Swift code validates paths, extensions, batch identities, and collisions before touching a file. Apple’s on-device model is the default; PCC is explicit opt-in, and Ollama can keep the fallback local.

I also copied the best part of the second half of Apple’s talk: measure it. The repo includes a locked Python prompt-evaluation harness and a bounded tool-calling experiment. The honest first six-case run is not a victory lap: it produced 0/6 exact decisions because folder routing missed the strict expected destinations. All four tool candidates were rejected by the predeclared quality/latency gate.

So I’m not claiming better model accuracy. I do think it is already a more complete, safer, and more usable product than the demo—and the failed benchmark is now the next piece of work rather than something hidden from the launch story.

Repository: https://github.com/tcballard/SortingHat

WWDC26 comparison and methodology: https://github.com/tcballard/SortingHat/blob/main/docs/wwdc26-comparison.md

I’d especially value feedback on the rule language, review flow, and what evidence you would want before trusting this with a real Inbox.

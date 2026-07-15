# Bounded filing-tool threat model

Tool calling is evaluation-only. No candidate is linked into the Swift package or accepted for production until a live representative-corpus run clears `tool-matrix.json`'s quality, failure, latency, and actual-use gates.

| Candidate | Intended value | Data available | Arguments | Result bound | Primary threats and controls |
| --- | --- | --- | --- | --- | --- |
| `destination_catalog` | Resolve ambiguous destination names | At most 32 configured folder/description pairs | Literal `all` only | 4,000 characters | No filesystem enumeration; catalog is copied from validated manifest data; entries are each capped at 120 characters. |
| `file_metadata` | Disambiguate otherwise similar files | Extension, coarse size bucket, declared corpus kind for the current case | One enum-selected field | 4,000 characters | No path argument, filename, timestamps, xattrs, owner, or arbitrary metadata query; values are prepared before the model call. |
| `content_segment` | Read beyond the common initial excerpt | At most 12,000 characters of text already extracted for the current case | Offset 0–12,000 and length 1–1,000 | 1,000 characters | No path or extraction API; arguments are range-checked again in `call`; four total calls maximum prevents iterative exfiltration. |
| `taxonomy_lookup` | Resolve user-defined labels or aliases | At most 64 exact key/value entries from the manifest | One enum-selected exact key | 4,000 characters | No fuzzy search, network, environment, or external database; unknown keys fail closed. |

## Shared boundaries

- `ToolContext` contains values, never a path, file descriptor, filesystem object, subprocess capability, or mutation callback.
- A session can make at most four tool calls. Tool outputs are JSON encoded and capped before return.
- Matrix configuration rejects unknown or repeated tools. PCC and image cases use the `fm` CLI transport, which is explicitly reported as unsupported for tools rather than silently dropping them.
- Corpus path validation remains in the evaluator. Tools cannot select another case or escape the corpus.
- Decisions still pass the canonical scoring contract. Tool output never moves, renames, tags, writes, deletes, or creates a file.
- An evaluated candidate is accepted only when it was actually called, improves accuracy by at least two percentage points, does not increase failures, and adds no more than 500 ms average latency. Otherwise the generated evidence says `REJECT`.

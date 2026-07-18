from __future__ import annotations

import argparse
import asyncio
from pathlib import Path

from .pipeline import compare_artifacts, run_pipeline


def default_resource(name: str) -> Path:
    """Resolve checked-in evaluation inputs from source and installed CLIs."""
    candidates = (
        Path.cwd() / name,
        Path.cwd() / "evaluation" / name,
        Path(__file__).parents[2] / name,
    )
    return next((path for path in candidates if path.is_file()), candidates[0])


def main() -> None:
    parser = argparse.ArgumentParser(description="Compare Sorting Hat prompt and Apple model variants")
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--corpus", type=Path)
    source.add_argument("--artifacts", type=Path, nargs="+")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--matrix", type=Path, default=default_resource("matrix.json"))
    parser.add_argument("--prompts", type=Path, default=default_resource("prompts.json"))
    parser.add_argument("--allow-pcc", action="store_true", help="allow corpus context to be sent to Apple PCC")
    args = parser.parse_args()
    if args.artifacts:
        artifact = compare_artifacts(args.artifacts, args.output)
    else:
        artifact = asyncio.run(run_pipeline(corpus_path=args.corpus, matrix_path=args.matrix,
                                            prompts_path=args.prompts, output=args.output, allow_pcc=args.allow_pcc))
    print(f"Compared {len(artifact['summaries'])} variants; wrote {args.output}")


if __name__ == "__main__":
    main()

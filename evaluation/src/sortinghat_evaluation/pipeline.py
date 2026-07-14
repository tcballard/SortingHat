from __future__ import annotations

import asyncio
import csv
import json
import platform
import subprocess
import tempfile
import time
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Protocol


@dataclass(frozen=True)
class Variant:
    id: str
    prompt: str
    model: str
    use_case: str


@dataclass
class CaseResult:
    variant: str
    case_id: str
    kind: str
    model: str
    use_case: str
    prompt_version: str
    transport: str
    os: str
    latency_ms: float
    output: dict[str, Any] | None
    error: str | None
    folder_correct: bool
    filename_correct: bool
    tags_correct: bool
    missing_information: int
    excess_information: int

    @property
    def correct(self) -> bool:
        return self.folder_correct and self.filename_correct and self.tags_correct and self.error is None


class Backend(Protocol):
    async def respond(self, *, variant: Variant, instructions: str, prompt: str,
                      source: Path) -> dict[str, Any]: ...


class AppleBackend:
    """Uses Apple's Python SDK for system variants and Apple's fm CLI for PCC."""

    async def respond(self, *, variant: Variant, instructions: str, prompt: str,
                      source: Path) -> dict[str, Any]:
        is_image = source.suffix.lower() in {".jpg", ".jpeg", ".png", ".heic", ".gif", ".tiff", ".webp"}
        if variant.model == "pcc" or is_image:
            return await asyncio.to_thread(self._respond_cli, variant, instructions, prompt, source)
        if variant.model != "system":
            raise ValueError(f"unsupported model: {variant.model}")
        import apple_fm_sdk as fm

        @fm.generable("A safe file organization decision")
        class SortingDecision:
            filename: str = fm.guide("A new descriptive filename preserving the extension")
            folder: str = fm.guide("A safe relative destination folder")
            tags: list[str] = fm.guide("A short list of useful Finder tags")
            reason: str = fm.guide("A concise reason")

        use_case = (fm.SystemLanguageModelUseCase.CONTENT_TAGGING
                    if variant.use_case == "content-tagging" else fm.SystemLanguageModelUseCase.GENERAL)
        model = fm.SystemLanguageModel(use_case=use_case)
        available, reason = model.is_available()
        if not available:
            raise RuntimeError(f"system model unavailable: {reason}")
        response = await fm.LanguageModelSession(model=model, instructions=instructions).respond(
            prompt=prompt, generating=SortingDecision)
        return {"filename": response.filename, "folder": response.folder,
                "tags": list(response.tags), "reason": response.reason}

    @staticmethod
    def _respond_cli(variant: Variant, instructions: str, prompt: str, source: Path) -> dict[str, Any]:
        schema = {
            "type": "object", "additionalProperties": False,
            "required": ["filename", "folder", "tags", "reason"],
            "properties": {
                "filename": {"type": "string"}, "folder": {"type": "string"},
                "tags": {"type": "array", "items": {"type": "string"}},
                "reason": {"type": "string"},
            },
        }
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json") as handle:
            json.dump(schema, handle); handle.flush()
            arguments = ["/usr/bin/fm", "respond", "--model", variant.model, "--instructions", instructions,
                         "--schema", handle.name, "--no-stream", "--greedy"]
            if variant.model == "system" and variant.use_case != "general":
                arguments.extend(["--use-case", variant.use_case])
            if source.suffix.lower() in {".jpg", ".jpeg", ".png", ".heic", ".gif", ".tiff", ".webp"}:
                arguments.extend(["--image", str(source), "--text"])
            arguments.append(prompt)
            completed = subprocess.run(
                arguments,
                check=True, capture_output=True, text=True,
            )
        return json.loads(completed.stdout)


def load_json(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def load_content(path: Path) -> str:
    if path.suffix.lower() in {".txt", ".md", ".csv", ".json", ".rtf"}:
        return path.read_text(encoding="utf-8", errors="replace")[:12_000]
    completed = subprocess.run(
        ["/usr/bin/mdls", "-raw", "-name", "kMDItemTextContent", str(path)],
        capture_output=True, text=True,
    )
    text = completed.stdout.strip()
    return text[:12_000] if completed.returncode == 0 and text not in {"", "(null)"} else "(No indexed text; classify from the filename.)"


def validate_inputs(corpus: dict[str, Any], matrix: dict[str, Any], prompts: dict[str, Any]) -> list[Variant]:
    if corpus.get("version") != 1 or matrix.get("version") != 1 or prompts.get("version") != 1:
        raise ValueError("corpus, matrix, and prompts must use version 1")
    variants = [Variant(**value) for value in matrix.get("variants", [])]
    if not variants or not corpus.get("cases"):
        raise ValueError("matrix variants and corpus cases cannot be empty")
    for variant in variants:
        if variant.prompt not in prompts["prompts"]:
            raise ValueError(f"unknown prompt: {variant.prompt}")
        if variant.model not in {"system", "pcc"}:
            raise ValueError(f"unknown model: {variant.model}")
        if variant.model == "pcc" and variant.use_case != "general":
            raise ValueError("PCC does not accept system-only use-case controls")
        if variant.use_case not in {"general", "content-tagging"}:
            raise ValueError(f"unknown use case: {variant.use_case}")
    return variants


async def run_pipeline(*, corpus_path: Path, matrix_path: Path, prompts_path: Path,
                       output: Path, backend: Backend | None = None, allow_pcc: bool = False) -> dict[str, Any]:
    corpus, matrix, prompt_data = load_json(corpus_path), load_json(matrix_path), load_json(prompts_path)
    variants = validate_inputs(corpus, matrix, prompt_data)
    if any(variant.model == "pcc" for variant in variants) and not allow_pcc:
        raise ValueError("matrix includes PCC; rerun with explicit PCC permission")
    backend = backend or AppleBackend()
    root, results = corpus_path.parent.resolve(), []
    os_version = platform.mac_ver()[0] or platform.platform()
    for variant in variants:
        prompt_variant = prompt_data["prompts"][variant.prompt]
        for case in corpus["cases"]:
            source = (root / case["path"]).resolve()
            if root not in source.parents or not source.is_file():
                raise ValueError(f"case {case['id']} is missing or escapes the corpus")
            prompt = prompt_variant["template"].format(
                rules="\n".join(f"- {rule}" for rule in corpus["rules"]),
                filename=source.name, content=load_content(source),
            )
            started, decision, error = time.perf_counter(), None, None
            try:
                decision = await backend.respond(variant=variant, instructions=prompt_variant["instructions"],
                                                 prompt=prompt, source=source)
            except Exception as exc:  # every failed generation remains a comparable row
                error = f"{type(exc).__name__}: {exc}"
            results.append(score(case, variant, os_version, (time.perf_counter() - started) * 1000, decision, error))
    artifact = {
        "schema_version": 1, "created_at": datetime.now(timezone.utc).isoformat(),
        "corpus_name": corpus["name"], "matrix": str(matrix_path),
        "results": [asdict(result) | {"correct": result.correct} for result in results],
        "summaries": summarize(results),
    }
    output.mkdir(parents=True, exist_ok=True)
    (output / "comparison.json").write_text(json.dumps(artifact, indent=2, sort_keys=True), encoding="utf-8")
    write_csv(output / "comparison.csv", artifact["summaries"])
    write_summary(output / "summary.md", artifact)
    render_charts(output / "comparison.png", artifact["summaries"])
    return artifact


def compare_artifacts(paths: list[Path], output: Path) -> dict[str, Any]:
    if len(paths) < 2:
        raise ValueError("artifact comparison requires at least two runs")
    rows: list[dict[str, Any]] = []
    corpora: set[str] = set()
    for path in paths:
        artifact = load_json(path)
        if artifact.get("schema_version") != 1:
            raise ValueError(f"unsupported artifact schema: {path}")
        corpora.add(artifact["corpus_name"])
        run = path.parent.name
        for summary_row in artifact["summaries"]:
            rows.append(dict(summary_row) | {"run": run, "variant": f"{run}:{summary_row['variant']}"})
    if len(corpora) != 1:
        raise ValueError("artifacts must use the same corpus")
    comparison = {"schema_version": 1, "corpus_name": corpora.pop(),
                  "artifacts": [str(path) for path in paths], "summaries": rows}
    output.mkdir(parents=True, exist_ok=True)
    (output / "comparison.json").write_text(json.dumps(comparison, indent=2, sort_keys=True), encoding="utf-8")
    write_csv(output / "comparison.csv", rows)
    write_summary(output / "summary.md", comparison)
    render_charts(output / "comparison.png", rows)
    return comparison


def score(case: dict[str, Any], variant: Variant, os_version: str, latency_ms: float,
          decision: dict[str, Any] | None, error: str | None) -> CaseResult:
    expected, decision = case["expected"], decision or {}
    filename = str(decision.get("filename", "")).lower()
    tags = {str(tag).lower() for tag in decision.get("tags", [])}
    expected_tags = {tag.lower() for tag in expected.get("tags", [])}
    terms = [term.lower() for term in expected.get("filename_contains", [])]
    folder_correct = decision.get("folder") in expected.get("folders", [])
    if expected.get("abstain"):
        folder_correct = not str(decision.get("folder", "")).strip()
    filename_correct = all(term in filename for term in terms)
    tags_correct = expected_tags <= tags
    missing = sum(term not in filename for term in terms) + len(expected_tags - tags)
    excess = len(tags - expected_tags)
    transport = "fm-cli" if variant.model == "pcc" or case["path"].lower().endswith(
        (".jpg", ".jpeg", ".png", ".heic", ".gif", ".tiff", ".webp")) else "python-sdk"
    return CaseResult(variant.id, case["id"], case["kind"], variant.model, variant.use_case,
                      variant.prompt, transport, os_version, latency_ms, decision or None, error,
                      folder_correct, filename_correct, tags_correct, missing, excess)


def summarize(results: list[CaseResult]) -> list[dict[str, Any]]:
    rows = []
    for variant in dict.fromkeys(result.variant for result in results):
        group = [result for result in results if result.variant == variant]
        count = len(group)
        rows.append({
            "variant": variant, "model": group[0].model, "use_case": group[0].use_case,
            "prompt_version": group[0].prompt_version,
            "accuracy": sum(result.correct for result in group) / count,
            "failure_rate": sum(result.error is not None for result in group) / count,
            "missing_information": sum(result.missing_information for result in group) / count,
            "excess_information": sum(result.excess_information for result in group) / count,
            "average_latency_ms": sum(result.latency_ms for result in group) / count,
        })
    return rows


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0])); writer.writeheader(); writer.writerows(rows)


def write_summary(path: Path, artifact: dict[str, Any]) -> None:
    lines = ["# Sorting Hat prompt comparison", "", f"Corpus: {artifact['corpus_name']}", "",
             "| Variant | Model | Use case | Prompt | Accuracy | Failures | Missing | Excess | Latency |",
             "| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |"]
    for row in artifact["summaries"]:
        lines.append(f"| {row['variant']} | {row['model']} | {row['use_case']} | {row['prompt_version']} | "
                     f"{row['accuracy']:.1%} | {row['failure_rate']:.1%} | {row['missing_information']:.2f} | "
                     f"{row['excess_information']:.2f} | {row['average_latency_ms']:.1f} ms |")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def render_charts(path: Path, rows: list[dict[str, Any]]) -> None:
    import matplotlib.pyplot as plt
    labels = [row["variant"] for row in rows]
    fig, axes = plt.subplots(2, 2, figsize=(13, 8), constrained_layout=True)
    series = [("accuracy", "Accuracy", "seagreen"), ("failure_rate", "Generation failures", "firebrick"),
              ("missing_information", "Missing / excess information", "darkorange"),
              ("average_latency_ms", "Average latency (ms)", "steelblue")]
    for axis, (key, title, color) in zip(axes.flat, series):
        axis.bar(labels, [row[key] for row in rows], color=color, label=key)
        if key == "missing_information":
            axis.bar(labels, [row["excess_information"] for row in rows], bottom=[row[key] for row in rows],
                     color="goldenrod", label="excess_information"); axis.legend()
        axis.set_title(title); axis.tick_params(axis="x", rotation=25)
    fig.suptitle("Sorting Hat Foundation Models prompt comparison")
    fig.savefig(path, dpi=180); plt.close(fig)

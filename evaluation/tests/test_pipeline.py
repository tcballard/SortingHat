import asyncio
import json
from pathlib import Path

from sortinghat_evaluation.pipeline import Variant, compare_artifacts, run_pipeline, score, summarize


class FakeBackend:
    async def respond(self, *, variant, instructions, prompt, source):
        if variant.id == "broken":
            raise RuntimeError("generation failed")
        return {"filename": "tesco-receipt.txt", "folder": "Receipts/2026",
                "tags": ["receipt", "tesco"], "reason": "receipt"}


def test_scores_missing_and_excess_information():
    case = {"id": "r1", "path": "receipt.txt", "kind": "receipt", "expected": {
        "folders": ["Receipts/2026"], "filename_contains": ["tesco", "receipt"],
        "tags": ["receipt"], "abstain": False}}
    result = score(case, Variant("v", "p", "system", "general"), "test", 12,
                   {"filename": "receipt.txt", "folder": "Receipts/2026", "tags": ["extra"], "reason": "x"}, None)
    assert not result.correct
    assert result.missing_information == 2
    assert result.excess_information == 1


def test_pipeline_compares_variants_and_writes_artifacts(tmp_path: Path, monkeypatch):
    corpus_dir = tmp_path / "corpus"; corpus_dir.mkdir()
    (corpus_dir / "receipt.txt").write_text("TESCO", encoding="utf-8")
    corpus = {"version": 1, "name": "synthetic", "rules": ["File receipts"], "cases": [{
        "id": "r1", "path": "receipt.txt", "kind": "receipt", "expected": {
            "folders": ["Receipts/2026"], "filename_contains": ["tesco", "receipt"],
            "tags": ["receipt"], "abstain": False}}]}
    matrix = {"version": 1, "variants": [
        {"id": "good", "prompt": "p1", "model": "system", "use_case": "general"},
        {"id": "broken", "prompt": "p1", "model": "system", "use_case": "content-tagging"}]}
    prompts = {"version": 1, "prompts": {"p1": {"instructions": "sort", "template": "{rules} {filename} {content}"}}}
    for path, value in [(corpus_dir / "corpus.json", corpus), (tmp_path / "matrix.json", matrix), (tmp_path / "prompts.json", prompts)]:
        path.write_text(json.dumps(value), encoding="utf-8")
    monkeypatch.setattr("sortinghat_evaluation.pipeline.render_charts", lambda path, rows: path.write_bytes(b"chart"))
    output = tmp_path / "results"
    artifact = asyncio.run(run_pipeline(corpus_path=corpus_dir / "corpus.json", matrix_path=tmp_path / "matrix.json",
                                        prompts_path=tmp_path / "prompts.json", output=output, backend=FakeBackend()))
    assert artifact["summaries"][0]["accuracy"] == 1
    assert artifact["summaries"][1]["failure_rate"] == 1
    assert {path.name for path in output.iterdir()} == {"comparison.json", "comparison.csv", "summary.md", "comparison.png"}


def test_summarizes_runs_by_variant():
    case = {"id": "r1", "path": "receipt.txt", "kind": "receipt", "expected": {"folders": ["Receipts"], "filename_contains": [], "tags": [], "abstain": False}}
    result = score(case, Variant("v", "p", "system", "general"), "test", 10,
                   {"filename": "renamed.txt", "folder": "Receipts", "tags": [], "reason": "x"}, None)
    assert summarize([result])[0]["average_latency_ms"] == 10


def test_compares_saved_runs_without_invoking_model(tmp_path: Path, monkeypatch):
    paths = []
    for run, accuracy in [("run-1", 0.5), ("run-2", 1.0)]:
        directory = tmp_path / run; directory.mkdir()
        path = directory / "comparison.json"
        path.write_text(json.dumps({"schema_version": 1, "corpus_name": "same", "summaries": [{
            "variant": "system", "model": "system", "use_case": "general", "prompt_version": "v1",
            "accuracy": accuracy, "failure_rate": 0, "missing_information": 0,
            "excess_information": 0, "average_latency_ms": 10}]}), encoding="utf-8")
        paths.append(path)
    monkeypatch.setattr("sortinghat_evaluation.pipeline.render_charts", lambda path, rows: path.write_bytes(b"chart"))
    comparison = compare_artifacts(paths, tmp_path / "compared")
    assert [row["accuracy"] for row in comparison["summaries"]] == [0.5, 1.0]
    assert comparison["summaries"][0]["variant"] == "run-1:system"


def test_requires_explicit_pcc_permission(tmp_path: Path):
    corpus = {"version": 1, "name": "synthetic", "rules": ["Sort"], "cases": [
        {"id": "one", "path": "one.txt", "kind": "text", "expected": {
            "folders": ["Files"], "filename_contains": [], "tags": [], "abstain": False}}]}
    matrix = {"version": 1, "variants": [
        {"id": "cloud", "prompt": "p1", "model": "pcc", "use_case": "general"}]}
    prompts = {"version": 1, "prompts": {"p1": {"instructions": "sort", "template": "{rules} {filename} {content}"}}}
    corpus_dir = tmp_path / "corpus"; corpus_dir.mkdir(); (corpus_dir / "one.txt").write_text("one")
    paths = []
    for name, value in [("corpus/corpus.json", corpus), ("matrix.json", matrix), ("prompts.json", prompts)]:
        path = tmp_path / name; path.write_text(json.dumps(value)); paths.append(path)
    try:
        asyncio.run(run_pipeline(corpus_path=paths[0], matrix_path=paths[1], prompts_path=paths[2],
                                 output=tmp_path / "output", backend=FakeBackend()))
        assert False, "PCC matrix should require explicit permission"
    except ValueError as error:
        assert "explicit PCC permission" in str(error)

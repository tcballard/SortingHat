import asyncio
import json
from pathlib import Path

import pytest

from sortinghat_evaluation.bounded_tools import MAX_SEGMENT_CHARACTERS, ToolContext, bounded_json
from sortinghat_evaluation.pipeline import (Variant, assess_tool_evidence, compare_artifacts,
                                            assess_tool_results, classify_error, run_pipeline, score,
                                            summarize, validate_inputs)


class FakeBackend:
    async def respond(self, *, variant, instructions, prompt, source, tool_context):
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


def test_tool_context_rejects_unbounded_or_sensitive_data():
    with pytest.raises(ValueError, match="non-permitted"):
        ToolContext(destinations=(), metadata={"path": "/private/file"}, content="", taxonomy={})
    with pytest.raises(ValueError, match="length limit"):
        ToolContext(destinations=(), metadata={}, content="x" * 12_001, taxonomy={})
    with pytest.raises(ValueError, match="length limit"):
        bounded_json({"result": "x" * 4_001})


def test_tool_call_budget_is_shared_across_candidates():
    context = ToolContext(destinations=(), metadata={}, content="content", taxonomy={})
    for _ in range(4):
        context.record("content_segment")
    with pytest.raises(ValueError, match="call limit"):
        context.record("file_metadata")


def test_tool_evidence_accepts_only_measurable_used_improvement():
    rows = [
        {"variant": "baseline", "enabled_tools": [], "accuracy": 0.7, "failure_rate": 0.1,
         "average_latency_ms": 100, "tool_calls": 0},
        {"variant": "useful", "enabled_tools": ["content_segment"], "accuracy": 0.8, "failure_rate": 0.1,
         "average_latency_ms": 200, "tool_calls": 3},
        {"variant": "unused", "enabled_tools": ["file_metadata"], "accuracy": 0.8, "failure_rate": 0.1,
         "average_latency_ms": 200, "tool_calls": 0},
    ]
    evidence = assess_tool_evidence(rows, {"baseline_variant": "baseline", "minimum_accuracy_uplift": 0.02,
                                           "maximum_failure_rate_increase": 0, "maximum_latency_increase_ms": 500})
    assert evidence["accepted"] == ["useful"]
    assert not evidence["candidates"][1]["accepted"]


def test_rejects_tools_on_unsupported_provider():
    corpus = {"version": 1, "cases": [{"id": "one"}]}
    matrix = {"version": 1, "variants": [{"id": "cloud", "prompt": "p", "model": "pcc",
                                              "use_case": "general", "tools": ["file_metadata"]}]}
    prompts = {"version": 1, "prompts": {"p": {}}}
    with pytest.raises(ValueError, match="only by the system"):
        validate_inputs(corpus, matrix, prompts)


def test_classifies_environment_and_unsupported_failures():
    assert classify_error("GenerationError: CriticalMemoryPressure") == "infrastructure"
    assert classify_error("ValueError: tool calling is unsupported by the fm CLI transport") == "unsupported_transport"
    assert classify_error("ValueError: malformed output") == "generation"
    assert classify_error("TimeoutError: model attempt exceeded 20 seconds") == "infrastructure"


def test_tool_evidence_is_inconclusive_when_model_infrastructure_fails():
    case = {"id": "r1", "path": "receipt.txt", "kind": "receipt", "expected": {
        "folders": ["Receipts"], "filename_contains": [], "tags": [], "abstain": False}}
    baseline = score(case, Variant("baseline", "p", "system", "general"), "test", 10,
                     None, "GenerationError: CriticalMemoryPressure")
    candidate = score(case, Variant("candidate", "p", "system", "general", ("file_metadata",)),
                      "test", 10, None, "GenerationError: CriticalMemoryPressure")
    evidence = assess_tool_results([baseline, candidate], {"baseline_variant": "baseline"})
    assert evidence["status"] == "inconclusive"
    assert evidence["accepted"] == []


def test_tool_evidence_isolated_to_candidate_with_infrastructure_failure():
    case = {"id": "r1", "path": "receipt.txt", "kind": "receipt", "expected": {
        "folders": ["Receipts"], "filename_contains": [], "tags": [], "abstain": False}}
    baseline = score(case, Variant("baseline", "p", "system", "general"), "test", 100,
                     {"filename": "receipt.txt", "folder": "Files", "tags": [], "reason": "x"}, None)
    useful = score(case, Variant("useful", "p", "system", "general", ("destination_catalog",)),
                   "test", 200, {"filename": "receipt.txt", "folder": "Receipts", "tags": [], "reason": "x"}, None,
                   {"destination_catalog": 1})
    broken = score(case, Variant("broken", "p", "system", "general", ("taxonomy_lookup",)),
                   "test", 10, None, "GenerationError: CriticalMemoryPressure")
    evidence = assess_tool_results([baseline, useful, broken], {
        "baseline_variant": "baseline", "minimum_accuracy_uplift": 0.02,
        "maximum_failure_rate_increase": 0, "maximum_latency_increase_ms": 500,
    })
    assert evidence["accepted"] == ["useful"]
    assert evidence["candidates"][1]["status"] == "inconclusive"

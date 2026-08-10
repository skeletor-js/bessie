#!/usr/bin/env python3
"""Evaluate numeric Bessie hardening evidence without collecting user data.

With no --input, this runs deterministic unit-level simulations. Those results
exercise aggregation and budget enforcement only; they are not startup or
terminal measurements from a packaged app.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path


BUDGETS = {
    "first_window_content_p95": (750.0, "p95"),
    "warm_shell_ready_p95": (1500.0, "p95"),
    "cold_shell_ready_p95": (3000.0, "p95"),
    "printable_key_to_visible_echo_p50": (25.0, "p50"),
    "printable_key_to_visible_echo_p95": (50.0, "p95"),
    "printable_key_to_visible_echo_p99": (100.0, "p99"),
    "frame_receive_to_libghostty_feed_p95": (8.0, "p95"),
    "startup_main_thread_stall_max": (100.0, "max"),
    "resize_convergence_max": (250.0, "max"),
}

SIMULATION = {
    "evidence_kind": "deterministic_simulation",
    "metrics": {
        "first_window_content_p95": [400, 450, 500, 550, 600],
        "warm_shell_ready_p95": [900, 1000, 1100, 1200, 1300],
        "cold_shell_ready_p95": [1800, 2000, 2200, 2400, 2600],
        "printable_key_to_visible_echo_p50": [10, 15, 20, 22, 24],
        "printable_key_to_visible_echo_p95": [20, 25, 30, 35, 40],
        "printable_key_to_visible_echo_p99": [30, 40, 50, 60, 70],
        "frame_receive_to_libghostty_feed_p95": [2, 3, 4, 5, 6],
        "startup_main_thread_stall_max": [20, 30, 40],
        "resize_convergence_max": [100, 120, 140],
    },
}

ALLOWED_EVIDENCE = {
    "deterministic_simulation",
    "packaged_local_measurement",
    "packaged_remote_measurement",
    "unavailable",
}

ALLOWED_MILESTONES = {
    "process_start", "app_start", "first_window_content", "runtime_validation", "connection_start",
    "snapshot_installed", "shell_ready", "terminal_controller_ready", "first_complete_frame",
    "startup_main_thread_probe_scheduled", "startup_main_thread_probe_completed",
    "terminal_input_received", "terminal_input_enqueued", "terminal_write_completed",
    "terminal_frame_received", "terminal_frame_fed", "terminal_frame_rendered",
    "terminal_switch_requested", "terminal_switch_surface_attached",
    "terminal_resize_requested", "terminal_resize_converged",
    "terminal_continuous_input_started", "terminal_continuous_input_visible",
    "terminal_continuous_output_started", "terminal_continuous_output_visible",
    "terminal_output_megabyte_started", "terminal_output_megabyte_visible",
    "terminal_output_lines_started", "terminal_output_lines_visible",
}


def percentile(samples: list[float], quantile: float) -> float:
    rank = max(1, math.ceil(quantile * len(samples)))
    return sorted(samples)[rank - 1]


def evaluate(payload: object) -> dict[str, object]:
    if not isinstance(payload, dict) or set(payload) != {"evidence_kind", "metrics"}:
        raise ValueError("evidence must contain only evidence_kind and metrics")
    evidence_kind = payload["evidence_kind"]
    metrics = payload["metrics"]
    if evidence_kind not in ALLOWED_EVIDENCE or not isinstance(metrics, dict):
        raise ValueError("invalid evidence_kind or metrics")
    if set(metrics) != set(BUDGETS):
        raise ValueError("metrics must exactly match the release budget set")

    results = []
    for metric, (limit, reducer) in BUDGETS.items():
        samples = metrics[metric]
        if not isinstance(samples, list) or not samples:
            raise ValueError(f"{metric} must contain finite nonnegative numeric samples")
        numeric = []
        for value in samples:
            if isinstance(value, bool) or not isinstance(value, (int, float)):
                raise ValueError(f"{metric} must contain finite nonnegative numeric samples")
            number = float(value)
            if not math.isfinite(number) or number < 0:
                raise ValueError(f"{metric} must contain finite nonnegative numeric samples")
            numeric.append(number)
        if reducer == "max":
            observed = max(numeric)
        else:
            observed = percentile(numeric, float(reducer[1:]) / 100)
        results.append({
            "metric": metric,
            "reducer": reducer,
            "sample_count": len(numeric),
            "observed_ms": observed,
            "budget_ms": limit,
            "passed": observed <= limit,
        })
    return {
        "schema_version": 1,
        "evidence_kind": evidence_kind,
        "simulation_is_not_live_measurement": evidence_kind == "deterministic_simulation",
        "passed": all(result["passed"] for result in results),
        "results": results,
    }


def evaluate_app_evidence(payload: object) -> dict[str, object]:
    if not isinstance(payload, dict) or set(payload) != {
        "schema_version", "evidence_kind", "milestones", "spans", "budgets"
    }:
        raise ValueError("app evidence has an unexpected top-level schema")
    if payload["schema_version"] != 1 or payload["evidence_kind"] not in ALLOWED_EVIDENCE:
        raise ValueError("unsupported app evidence schema or evidence kind")

    milestones = payload["milestones"]
    spans = payload["spans"]
    budgets = payload["budgets"]
    if not isinstance(milestones, list) or not isinstance(spans, list) or not isinstance(budgets, list):
        raise ValueError("app evidence collections must be arrays")

    def numeric(value: object, field: str) -> float:
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise ValueError(f"{field} must be a finite nonnegative number")
        number = float(value)
        if not math.isfinite(number) or number < 0:
            raise ValueError(f"{field} must be a finite nonnegative number")
        return number

    def sequence(value: object) -> None:
        if isinstance(value, bool) or not isinstance(value, int) or value < 0:
            raise ValueError("sequence must be an opaque nonnegative integer")

    for mark in milestones:
        if not isinstance(mark, dict) or not {"milestone", "elapsed_ms"}.issubset(mark) \
                or not set(mark).issubset({"milestone", "sequence", "elapsed_ms"}):
            raise ValueError("invalid milestone record schema")
        if mark["milestone"] not in ALLOWED_MILESTONES:
            raise ValueError("unknown milestone")
        numeric(mark["elapsed_ms"], "elapsed_ms")
        if "sequence" in mark:
            sequence(mark["sequence"])

    for span in spans:
        required = {"start_milestone", "end_milestone", "budget_verdict"}
        allowed = required | {"sequence", "duration_ms"}
        if not isinstance(span, dict) or not required.issubset(span) or not set(span).issubset(allowed):
            raise ValueError("invalid span record schema")
        if span["start_milestone"] not in ALLOWED_MILESTONES or span["end_milestone"] not in ALLOWED_MILESTONES:
            raise ValueError("unknown span milestone")
        if span["budget_verdict"] not in {"passed", "failed", "unavailable", "not_evaluated"}:
            raise ValueError("invalid span budget verdict")
        if "sequence" in span:
            sequence(span["sequence"])
        if "duration_ms" in span:
            numeric(span["duration_ms"], "duration_ms")

    by_metric = {}
    for budget in budgets:
        required = {"metric", "budget_verdict"}
        allowed = required | {"observed_ms"}
        if not isinstance(budget, dict) or not required.issubset(budget) or not set(budget).issubset(allowed):
            raise ValueError("invalid budget record schema")
        metric = budget["metric"]
        verdict = budget["budget_verdict"]
        if metric not in BUDGETS or verdict not in {"passed", "failed", "unavailable"}:
            raise ValueError("unknown budget metric or verdict")
        if metric in by_metric:
            raise ValueError("duplicate budget metric")
        observed = numeric(budget["observed_ms"], "observed_ms") if "observed_ms" in budget else None
        if verdict == "unavailable" and observed is not None:
            raise ValueError("unavailable budget must not contain an observation")
        if verdict != "unavailable" and observed is None:
            raise ValueError("evaluated budget requires an observation")
        by_metric[metric] = {"metric": metric, "observed_ms": observed, "budget_verdict": verdict}
    if set(by_metric) != set(BUDGETS):
        raise ValueError("app evidence budgets must exactly match the release budget set")

    results = [by_metric[metric] for metric in BUDGETS]
    has_failures = any(result["budget_verdict"] == "failed" for result in results)
    unavailable = [result["metric"] for result in results if result["budget_verdict"] == "unavailable"]
    return {
        "schema_version": 1,
        "evidence_kind": payload["evidence_kind"],
        "simulation_is_not_live_measurement": False,
        "evidence_complete": not unavailable,
        "has_failures": has_failures,
        "unavailable_metrics": unavailable,
        "milestone_count": len(milestones),
        "span_count": len(spans),
        "results": results,
    }


def evaluate_terminal_plan(payload: object, resources: object) -> dict[str, object]:
    evaluate_app_evidence(payload)
    if not isinstance(resources, dict) or set(resources) != {
        "duration_seconds", "sample_interval_seconds", "cpu_percent", "idle_cpu_percent", "rss_mb",
    }:
        raise ValueError("resource evidence has an unexpected schema")

    def number(value: object, field: str) -> float:
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise ValueError(f"{field} must be a finite nonnegative number")
        result = float(value)
        if not math.isfinite(result) or result < 0:
            raise ValueError(f"{field} must be a finite nonnegative number")
        return result

    def numbers(value: object, field: str) -> list[float]:
        if not isinstance(value, list) or not value:
            raise ValueError(f"{field} must be a nonempty array")
        return [number(item, field) for item in value]

    spans = payload["spans"]

    def durations(start: str, end: str) -> list[float]:
        return [
            number(span["duration_ms"], "duration_ms")
            for span in spans
            if span.get("start_milestone") == start
            and span.get("end_milestone") == end
            and "duration_ms" in span
        ]

    echo = durations("terminal_input_received", "terminal_frame_rendered")
    frame_feed = durations("terminal_frame_received", "terminal_frame_fed")
    switches = durations("terminal_switch_requested", "terminal_switch_surface_attached")
    resize = durations("terminal_resize_requested", "terminal_resize_converged")
    continuous_input = durations("terminal_continuous_input_started", "terminal_continuous_input_visible")
    continuous_output = durations("terminal_continuous_output_started", "terminal_continuous_output_visible")
    megabyte = durations("terminal_output_megabyte_started", "terminal_output_megabyte_visible")
    lines = durations("terminal_output_lines_started", "terminal_output_lines_visible")
    cpu = numbers(resources["cpu_percent"], "cpu_percent")
    idle_cpu = numbers(resources["idle_cpu_percent"], "idle_cpu_percent")
    rss = numbers(resources["rss_mb"], "rss_mb")
    duration = number(resources["duration_seconds"], "duration_seconds")
    interval = number(resources["sample_interval_seconds"], "sample_interval_seconds")
    if interval <= 0:
        raise ValueError("sample_interval_seconds must be greater than zero")

    longest_high_run = 0
    current_high_run = 0
    for sample in cpu:
        current_high_run = current_high_run + 1 if sample > 80 else 0
        longest_high_run = max(longest_high_run, current_high_run)

    def result(metric: str, observed: float, budget: float, count: int, passed: bool) -> dict[str, object]:
        return {
            "metric": metric,
            "observed": observed,
            "budget": budget,
            "sample_count": count,
            "passed": passed,
        }

    results = [
        result("printable_echo_p50_ms", percentile(echo, 0.50) if echo else math.inf, 25, len(echo), len(echo) >= 200 and percentile(echo, 0.50) <= 25),
        result("printable_echo_p95_ms", percentile(echo, 0.95) if echo else math.inf, 50, len(echo), len(echo) >= 200 and percentile(echo, 0.95) <= 50),
        result("printable_echo_p99_ms", percentile(echo, 0.99) if echo else math.inf, 100, len(echo), len(echo) >= 200 and percentile(echo, 0.99) <= 100),
        result("frame_receive_to_feed_p95_ms", percentile(frame_feed, 0.95) if frame_feed else math.inf, 8, len(frame_feed), len(frame_feed) >= 20 and percentile(frame_feed, 0.95) <= 8),
        result("one_megabyte_output_max_ms", max(megabyte) if megabyte else math.inf, 250, len(megabyte), len(megabyte) >= 5 and max(megabyte) <= 250),
        result("fifty_thousand_lines_max_ms", max(lines) if lines else math.inf, 1_000, len(lines), len(lines) >= 5 and max(lines) <= 1_000),
        result("pane_switch_first_usable_max_ms", max(switches) if switches else math.inf, 100, len(switches), len(switches) >= 20 and max(switches) <= 100),
        result("resize_convergence_max_ms", max(resize) if resize else math.inf, 250, len(resize), len(resize) >= 1 and max(resize) <= 250),
        result("continuous_output_input_max_ms", max(continuous_input) if continuous_input else math.inf, 100, len(continuous_input), len(continuous_input) >= 100 and max(continuous_input) <= 100),
        result("five_minute_cpu_average_percent", sum(cpu) / len(cpu), 35, len(cpu), duration >= 300 and sum(cpu) / len(cpu) < 35),
        result("cpu_over_80_longest_seconds", longest_high_run * interval, 2, len(cpu), longest_high_run * interval <= 2),
        result("idle_cpu_average_percent", sum(idle_cpu) / len(idle_cpu), 2, len(idle_cpu), sum(idle_cpu) / len(idle_cpu) < 2),
        result("resident_memory_max_mb", max(rss), 300, len(rss), max(rss) <= 300),
        result(
            "continuous_output_seconds",
            min(continuous_output) / 1_000 if continuous_output else math.inf,
            60,
            len(continuous_output),
            len(continuous_output) >= 1 and min(continuous_output) >= 60_000,
        ),
    ]
    return {
        "schema_version": 1,
        "evidence_kind": payload["evidence_kind"],
        "terminal_plan": True,
        "passed": all(item["passed"] for item in results),
        "results": results,
    }


def evaluate_startup_samples(payload: object) -> dict[str, object]:
    expected = {
        "evidence_kind", "first_window_content_ms", "warm_shell_ready_ms",
        "cold_shell_ready_ms", "startup_main_thread_stall_ms",
    }
    if not isinstance(payload, dict) or set(payload) != expected:
        raise ValueError("startup evidence has an unexpected schema")
    if payload["evidence_kind"] != "packaged_local_measurement":
        raise ValueError("startup evidence must be a packaged local measurement")

    def numbers(field: str, minimum_count: int = 20) -> list[float]:
        value = payload[field]
        if not isinstance(value, list) or len(value) < minimum_count:
            raise ValueError(f"{field} must contain at least {minimum_count} samples")
        result = []
        for item in value:
            if isinstance(item, bool) or not isinstance(item, (int, float)):
                raise ValueError(f"{field} must contain finite nonnegative numbers")
            number = float(item)
            if not math.isfinite(number) or number < 0:
                raise ValueError(f"{field} must contain finite nonnegative numbers")
            result.append(number)
        return result

    first_window = numbers("first_window_content_ms")
    warm_shell = numbers("warm_shell_ready_ms")
    cold_shell = numbers("cold_shell_ready_ms", minimum_count=5)
    main_thread = numbers("startup_main_thread_stall_ms")

    def result(metric: str, observed: float, budget: float, count: int) -> dict[str, object]:
        return {
            "metric": metric,
            "observed": observed,
            "budget": budget,
            "sample_count": count,
            "passed": observed <= budget,
        }

    results = [
        result("first_window_content_p95_ms", percentile(first_window, 0.95), 750, len(first_window)),
        result("warm_shell_ready_p95_ms", percentile(warm_shell, 0.95), 1_500, len(warm_shell)),
        result("cold_shell_ready_p95_ms", percentile(cold_shell, 0.95), 3_000, len(cold_shell)),
        result("startup_main_thread_stall_max_ms", max(main_thread), 100, len(main_thread)),
    ]
    return {
        "schema_version": 1,
        "evidence_kind": payload["evidence_kind"],
        "startup_plan": True,
        "passed": all(item["passed"] for item in results),
        "results": results,
    }


def terminal_text_report(report: dict[str, object]) -> str:
    lines = [f"evidence_kind: {report['evidence_kind']}", "terminal_plan: true"]
    for result in report["results"]:
        observed = result["observed"]
        observed_text = "unavailable" if not math.isfinite(observed) else f"{observed:g}"
        lines.append(
            f"{'PASS' if result['passed'] else 'FAIL'} {result['metric']} "
            f"observed={observed_text} budget={result['budget']:g} samples={result['sample_count']}"
        )
    lines.append(f"overall: {'PASS' if report['passed'] else 'FAIL'}")
    return "\n".join(lines)


def startup_text_report(report: dict[str, object]) -> str:
    lines = [f"evidence_kind: {report['evidence_kind']}", "startup_plan: true"]
    for result in report["results"]:
        lines.append(
            f"{'PASS' if result['passed'] else 'FAIL'} {result['metric']} "
            f"observed={result['observed']:g} budget={result['budget']:g} samples={result['sample_count']}"
        )
    lines.append(f"overall: {'PASS' if report['passed'] else 'FAIL'}")
    return "\n".join(lines)


def text_report(report: dict[str, object]) -> str:
    lines = [
        f"evidence_kind: {report['evidence_kind']}",
        f"simulation_is_not_live_measurement: {str(report['simulation_is_not_live_measurement']).lower()}",
    ]
    if "evidence_complete" in report:
        lines.extend([
            f"evidence_complete: {str(report['evidence_complete']).lower()}",
            f"milestones: {report['milestone_count']}",
            f"spans: {report['span_count']}",
        ])
        for result in report["results"]:
            verdict = result["budget_verdict"].upper()
            observed = "unavailable" if result["observed_ms"] is None else f"{result['observed_ms']:g}ms"
            lines.append(f"{verdict} {result['metric']} observed={observed}")
        overall = "FAIL" if report["has_failures"] else ("PASS" if report["evidence_complete"] else "INCOMPLETE")
        lines.append(f"overall: {overall}")
        return "\n".join(lines)
    for result in report["results"]:
        lines.append(
            f"{'PASS' if result['passed'] else 'FAIL'} {result['metric']} "
            f"{result['reducer']}={result['observed_ms']:g}ms budget={result['budget_ms']:g}ms "
            f"samples={result['sample_count']}"
        )
    lines.append(f"overall: {'PASS' if report['passed'] else 'FAIL'}")
    return "\n".join(lines)


def report_exit_code(report: dict[str, object]) -> int:
    if "has_failures" in report:
        return 0 if report["evidence_complete"] and not report["has_failures"] else 1
    return 0 if report["passed"] else 1


def self_test() -> None:
    assert evaluate(SIMULATION)["passed"] is True
    failing = json.loads(json.dumps(SIMULATION))
    failing["metrics"]["frame_receive_to_libghostty_feed_p95"] = [9]
    assert evaluate(failing)["passed"] is False
    try:
        evaluate({"evidence_kind": "deterministic_simulation", "metrics": {}, "secret": "no"})
    except ValueError:
        pass
    else:
        raise AssertionError("unexpected fields must be rejected")
    exported = {
        "schema_version": 1,
        "evidence_kind": "packaged_local_measurement",
        "milestones": [{"milestone": "process_start", "elapsed_ms": 0.0}],
        "spans": [{
            "start_milestone": "terminal_input_received",
            "end_milestone": "terminal_frame_rendered",
            "sequence": 1,
            "budget_verdict": "unavailable",
        }],
        "budgets": [
            {"metric": metric, "budget_verdict": "unavailable"} for metric in BUDGETS
        ],
    }
    report = evaluate_app_evidence(exported)
    assert report["evidence_complete"] is False
    assert report["has_failures"] is False
    assert report_exit_code(report) == 1
    complete = json.loads(json.dumps(exported))
    complete["budgets"] = [
        {"metric": metric, "observed_ms": 1.0, "budget_verdict": "passed"} for metric in BUDGETS
    ]
    assert report_exit_code(evaluate_app_evidence(complete)) == 0
    failing_export = json.loads(json.dumps(complete))
    failing_export["budgets"][0]["budget_verdict"] = "failed"
    assert report_exit_code(evaluate_app_evidence(failing_export)) == 1

    terminal_export = json.loads(json.dumps(complete))
    terminal_export["spans"] = []
    definitions = [
        ("terminal_input_received", "terminal_frame_rendered", 200, 20.0),
        ("terminal_frame_received", "terminal_frame_fed", 20, 2.0),
        ("terminal_switch_requested", "terminal_switch_surface_attached", 20, 40.0),
        ("terminal_resize_requested", "terminal_resize_converged", 1, 200.0),
        ("terminal_continuous_input_started", "terminal_continuous_input_visible", 100, 50.0),
        ("terminal_continuous_output_started", "terminal_continuous_output_visible", 1, 65_000.0),
        ("terminal_output_megabyte_started", "terminal_output_megabyte_visible", 5, 200.0),
        ("terminal_output_lines_started", "terminal_output_lines_visible", 5, 800.0),
    ]
    for start, end, count, duration in definitions:
        terminal_export["spans"].extend({
            "start_milestone": start,
            "end_milestone": end,
            "sequence": index,
            "duration_ms": duration,
            "budget_verdict": "not_evaluated",
        } for index in range(count))
    resources = {
        "duration_seconds": 300,
        "sample_interval_seconds": 1,
        "cpu_percent": [20] * 300,
        "idle_cpu_percent": [1] * 30,
        "rss_mb": [200] * 300,
    }
    assert evaluate_terminal_plan(terminal_export, resources)["passed"] is True
    resources["idle_cpu_percent"] = [2]
    assert evaluate_terminal_plan(terminal_export, resources)["passed"] is False

    startup = {
        "evidence_kind": "packaged_local_measurement",
        "first_window_content_ms": [500] * 20,
        "warm_shell_ready_ms": [1_000] * 20,
        "cold_shell_ready_ms": [2_000] * 5,
        "startup_main_thread_stall_ms": [50] * 20,
    }
    assert evaluate_startup_samples(startup)["passed"] is True
    startup["cold_shell_ready_ms"][-2:] = [3_001, 3_001]
    assert evaluate_startup_samples(startup)["passed"] is False
    startup["cold_shell_ready_ms"] = [2_000] * 4
    try:
        evaluate_startup_samples(startup)
    except ValueError:
        pass
    else:
        raise AssertionError("startup cold-shell evidence requires five samples")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, help="strict numeric evidence JSON; defaults to labeled simulation")
    parser.add_argument("--app-evidence", type=Path, help="payload-free evidence exported by the packaged app")
    parser.add_argument("--terminal-app-evidence", type=Path, help="app evidence for the terminal performance plan")
    parser.add_argument("--resource-samples", type=Path, help="payload-free CPU and memory samples for the terminal performance plan")
    parser.add_argument("--startup-samples", type=Path, help="aggregated packaged-app startup samples")
    parser.add_argument("--format", choices=("json", "text"), default="text")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    selected = [
        args.input is not None,
        args.app_evidence is not None,
        args.terminal_app_evidence is not None,
        args.startup_samples is not None,
    ]
    if sum(selected) > 1:
        parser.error("--input, --app-evidence, --terminal-app-evidence, and --startup-samples are mutually exclusive")
    if (args.terminal_app_evidence is None) != (args.resource_samples is None):
        parser.error("--terminal-app-evidence and --resource-samples must be used together")
    try:
        if args.terminal_app_evidence:
            report = evaluate_terminal_plan(
                json.loads(args.terminal_app_evidence.read_text()),
                json.loads(args.resource_samples.read_text()),
            )
        elif args.startup_samples:
            report = evaluate_startup_samples(json.loads(args.startup_samples.read_text()))
        elif args.app_evidence:
            report = evaluate_app_evidence(json.loads(args.app_evidence.read_text()))
        else:
            payload = json.loads(args.input.read_text()) if args.input else SIMULATION
            report = evaluate(payload)
    except (OSError, json.JSONDecodeError, ValueError) as error:
        print(f"hardening benchmark input error: {error}", file=sys.stderr)
        return 2
    if args.format == "json":
        print(json.dumps(report, indent=2, sort_keys=True))
    elif report.get("terminal_plan"):
        print(terminal_text_report(report))
    elif report.get("startup_plan"):
        print(startup_text_report(report))
    else:
        print(text_report(report))
    return 0 if report.get("passed") else report_exit_code(report)


if __name__ == "__main__":
    raise SystemExit(main())

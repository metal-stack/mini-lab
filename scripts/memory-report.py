#!/usr/bin/env python3
"""Turn memory traces produced by memory-trace.py into readable reports.

Two subcommands:

    summarize   one trace  -> summary.json + summary.md
    compare     many runs  -> comparison.md (profiles side by side per flavor)
"""

import argparse
import csv
import json
import statistics
import sys
from pathlib import Path

# containers that hold a QEMU VM; used for the "lab footprint" aggregate
VM_PREFIXES = ("leaf", "machine")

SPARK = "▁▂▃▄▅▆▇█"


def mib(kb: float | None) -> float | None:
    return None if kb is None else round(kb / 1024, 1)


def gib(kb: float | None) -> float | None:
    return None if kb is None else round(kb / 1024 / 1024, 2)


def fmt(value, unit="GiB") -> str:
    if value is None:
        return "n/a"
    return f"{value:.2f} {unit}" if unit else f"{value:.2f}"


def sparkline(values: list[float]) -> str:
    if not values:
        return ""
    lo, hi = min(values), max(values)
    if hi - lo < 1e-9:
        return SPARK[0] * min(len(values), 60)
    # downsample to at most 60 buckets
    width = min(len(values), 60)
    step = len(values) / width
    out = []
    for i in range(width):
        chunk = values[int(i * step):max(int((i + 1) * step), int(i * step) + 1)]
        avg = sum(chunk) / len(chunk)
        idx = int((avg - lo) / (hi - lo) * (len(SPARK) - 1))
        out.append(SPARK[idx])
    return "".join(out)


def load_trace(path: Path) -> dict:
    """Return {(scope, name, metric): [(elapsed, value), ...]}."""
    series: dict = {}
    with path.open(newline="") as fh:
        reader = csv.DictReader(fh)
        for row in reader:
            try:
                elapsed = float(row["elapsed_s"])
                value = float(row["value"])
            except (TypeError, ValueError):
                continue
            key = (row["scope"], row["name"], row["metric"])
            series.setdefault(key, []).append((elapsed, value))
    return series


def container_sum_over_time(series: dict, metric: str) -> list[tuple[float, float]]:
    """Sum a per-container metric across containers at each sample time."""
    by_time: dict = {}
    for (scope, _name, m), points in series.items():
        if scope != "container" or m != metric:
            continue
        for elapsed, value in points:
            by_time[elapsed] = by_time.get(elapsed, 0.0) + value
    return sorted(by_time.items())


def vm_sum_over_time(series: dict, metric: str) -> list[tuple[float, float]]:
    by_time: dict = {}
    for (scope, name, m), points in series.items():
        if scope != "container" or m != metric:
            continue
        if not name.startswith(VM_PREFIXES):
            continue
        for elapsed, value in points:
            by_time[elapsed] = by_time.get(elapsed, 0.0) + value
    return sorted(by_time.items())


def peak(points: list[tuple[float, float]]) -> float | None:
    return max((v for _, v in points), default=None)


def mean(points: list[tuple[float, float]]) -> float | None:
    values = [v for _, v in points]
    return statistics.fmean(values) if values else None


def cmd_summarize(args: argparse.Namespace) -> int:
    trace = Path(args.trace)
    if not trace.exists():
        print(f"trace not found: {trace}", file=sys.stderr)
        return 1

    series = load_trace(trace)
    if not series:
        print(f"trace is empty: {trace}", file=sys.stderr)
        return 1

    meta = {}
    if args.meta and Path(args.meta).exists():
        meta = json.loads(Path(args.meta).read_text())

    host_used = next((p for (s, _n, m), p in series.items()
                      if s == "host" and m == "mem_used_kb"), [])
    host_swap = next((p for (s, _n, m), p in series.items()
                      if s == "host" and m == "swap_used_kb"), [])
    ksm_saved = next((p for (s, _n, m), p in series.items()
                      if s == "host" and m == "ksm_saved_kb"), [])
    host_thp = next((p for (s, _n, m), p in series.items()
                     if s == "host" and m == "anon_hugepages_kb"), [])

    lab_total = container_sum_over_time(series, "mem_current_kb")
    vm_total = vm_sum_over_time(series, "mem_current_kb")
    qemu_total = vm_sum_over_time(series, "qemu_rss_kb")

    duration = max((e for e, _ in host_used), default=0.0)

    per_container = {}
    for (scope, name, metric), points in sorted(series.items()):
        if scope != "container" or metric not in ("mem_current_kb", "qemu_rss_kb"):
            continue
        entry = per_container.setdefault(name, {})
        entry[f"{metric}_peak"] = peak(points)
        entry[f"{metric}_mean"] = mean(points)

    summary = {
        "flavor": meta.get("flavor") or args.flavor,
        "profile": meta.get("profile") or args.profile,
        "duration_s": round(duration, 1),
        "samples": len(host_used),
        "meta": meta,
        "host": {
            "mem_used_peak_kb": peak(host_used),
            "mem_used_mean_kb": mean(host_used),
            "swap_used_peak_kb": peak(host_swap),
            "ksm_saved_peak_kb": peak(ksm_saved),
            "anon_hugepages_peak_kb": peak(host_thp),
        },
        "lab": {
            "containers_peak_kb": peak(lab_total),
            "vm_containers_peak_kb": peak(vm_total),
            "vm_containers_mean_kb": mean(vm_total),
            "qemu_rss_peak_kb": peak(qemu_total),
        },
        "containers": per_container,
    }

    if args.out_json:
        out = Path(args.out_json)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(summary, indent=2) + "\n")

    md = render_summary(summary, host_used, vm_total)
    if args.out_md:
        out = Path(args.out_md)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(md)
    else:
        print(md)
    return 0


def render_summary(summary: dict, host_used, vm_total) -> str:
    host = summary["host"]
    lab = summary["lab"]
    meta = summary.get("meta", {})

    lines = [
        f"## Memory trace — flavor `{summary['flavor'] or 'unknown'}`, "
        f"profile `{summary['profile'] or 'unknown'}`",
        "",
        f"- duration: {summary['duration_s']:.0f}s ({summary['samples']} samples)",
        f"- leaf memory: {meta.get('leaf_memory_mb') or 'default'} MB, "
        f"machine memory: {meta.get('machine_memory_mb') or 'default'} MB",
        f"- KSM: {'on' if meta.get('ksm_run') else 'off'}, "
        f"THP: {meta.get('thp_setting', 'unknown')}",
        "",
        "| metric | peak | mean |",
        "| --- | --- | --- |",
        f"| host memory used | {fmt(gib(host['mem_used_peak_kb']))} | "
        f"{fmt(gib(host['mem_used_mean_kb']))} |",
        f"| host swap used | {fmt(gib(host['swap_used_peak_kb']))} | — |",
        f"| all containers | {fmt(gib(lab['containers_peak_kb']))} | — |",
        f"| VM containers | {fmt(gib(lab['vm_containers_peak_kb']))} | "
        f"{fmt(gib(lab['vm_containers_mean_kb']))} |",
        f"| QEMU RSS (all VMs) | {fmt(gib(lab['qemu_rss_peak_kb']))} | — |",
        f"| KSM saved | {fmt(gib(host['ksm_saved_peak_kb']))} | — |",
        "",
    ]

    if host_used:
        lines += [
            "```",
            f"host used   {sparkline([v for _, v in host_used])}  "
            f"{fmt(gib(host['mem_used_peak_kb']))} peak",
            f"VM totals   {sparkline([v for _, v in vm_total])}  "
            f"{fmt(gib(lab['vm_containers_peak_kb']))} peak",
            "```",
            "",
        ]

    lines += ["| container | peak | mean | QEMU RSS peak |", "| --- | --- | --- | --- |"]
    for name, entry in sorted(summary["containers"].items(),
                              key=lambda kv: -(kv[1].get("mem_current_kb_peak") or 0)):
        lines.append(
            f"| {name} | {fmt(gib(entry.get('mem_current_kb_peak')))} | "
            f"{fmt(gib(entry.get('mem_current_kb_mean')))} | "
            f"{fmt(gib(entry.get('qemu_rss_kb_peak')))} |"
        )
    lines.append("")
    return "\n".join(lines)


def cmd_compare(args: argparse.Namespace) -> int:
    summaries = []
    for path in sorted(Path(args.input_dir).rglob("summary.json")):
        try:
            summaries.append(json.loads(path.read_text()))
        except (OSError, json.JSONDecodeError) as exc:
            print(f"skipping {path}: {exc}", file=sys.stderr)
    if not summaries:
        print(f"no summary.json found under {args.input_dir}", file=sys.stderr)
        return 1

    by_flavor: dict = {}
    for summary in summaries:
        by_flavor.setdefault(summary.get("flavor") or "unknown", []).append(summary)

    lines = ["# Memory profile comparison", ""]
    lines += [
        "Peak values across the whole integration run. `Δ` columns compare "
        "against the `baseline` profile of the same flavor.",
        "",
    ]

    for flavor in sorted(by_flavor):
        runs = by_flavor[flavor]
        baseline = next((r for r in runs if r.get("profile") == args.baseline), None)
        base_host = (baseline or {}).get("host", {}).get("mem_used_peak_kb")
        base_vm = (baseline or {}).get("lab", {}).get("vm_containers_peak_kb")

        lines += [
            f"## `{flavor}`",
            "",
            "| profile | host used (peak) | Δ host | VM containers (peak) | "
            "Δ VMs | QEMU RSS (peak) | swap (peak) | KSM saved | duration |",
            "| --- | --- | --- | --- | --- | --- | --- | --- | --- |",
        ]

        def sort_key(run):
            profile = run.get("profile") or ""
            return (profile != args.baseline, profile)

        for run in sorted(runs, key=sort_key):
            host = run.get("host", {})
            lab = run.get("lab", {})

            is_baseline = run.get("profile") == args.baseline

            def delta(value, base, is_baseline=is_baseline):
                if is_baseline or value is None or base is None:
                    return "—"
                diff = gib(value - base)
                pct = (value - base) / base * 100 if base else 0
                sign = "+" if diff >= 0 else ""
                return f"{sign}{diff:.2f} GiB ({sign}{pct:.1f}%)"

            lines.append(
                f"| `{run.get('profile') or 'unknown'}` "
                f"| {fmt(gib(host.get('mem_used_peak_kb')))} "
                f"| {delta(host.get('mem_used_peak_kb'), base_host)} "
                f"| {fmt(gib(lab.get('vm_containers_peak_kb')))} "
                f"| {delta(lab.get('vm_containers_peak_kb'), base_vm)} "
                f"| {fmt(gib(lab.get('qemu_rss_peak_kb')))} "
                f"| {fmt(gib(host.get('swap_used_peak_kb')))} "
                f"| {fmt(gib(host.get('ksm_saved_peak_kb')))} "
                f"| {run.get('duration_s', 0):.0f}s |"
            )
        lines.append("")

    md = "\n".join(lines)
    if args.out_md:
        out = Path(args.out_md)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(md)
    else:
        print(md)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    s = sub.add_parser("summarize", help="summarize a single trace")
    s.add_argument("--trace", required=True)
    s.add_argument("--meta")
    s.add_argument("--out-json")
    s.add_argument("--out-md")
    s.add_argument("--flavor", default="")
    s.add_argument("--profile", default="")
    s.set_defaults(func=cmd_summarize)

    c = sub.add_parser("compare", help="compare summaries of several runs")
    c.add_argument("--input-dir", required=True)
    c.add_argument("--out-md")
    c.add_argument("--baseline", default="baseline")
    c.set_defaults(func=cmd_compare)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())

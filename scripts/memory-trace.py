#!/usr/bin/env python3
"""Sample host and per-container memory usage into a CSV trace.

Runs until it receives SIGTERM/SIGINT, appending one row per subject per
sampling interval. Everything it reads (/proc, /sys/fs/cgroup) is world
readable, so no root privileges are required even though the QEMU processes
themselves belong to root.

The trace is written in long format so that new metrics can be added without
breaking existing consumers:

    ts,elapsed_s,scope,name,metric,value

Metric names carry their unit as a suffix (``_kb``), except for plain flags
and counters.
"""

import argparse
import csv
import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

CGROUP_ROOT = Path("/sys/fs/cgroup")
KSM_ROOT = Path("/sys/kernel/mm/ksm")
PAGE_SIZE_KB = os.sysconf("SC_PAGE_SIZE") // 1024

# /proc/meminfo keys we care about, mapped to the metric name we emit
MEMINFO_KEYS = {
    "MemTotal": "mem_total_kb",
    "MemFree": "mem_free_kb",
    "MemAvailable": "mem_available_kb",
    "Cached": "cached_kb",
    "AnonPages": "anon_kb",
    "AnonHugePages": "anon_hugepages_kb",
    "SwapTotal": "swap_total_kb",
    "SwapFree": "swap_free_kb",
}

_running = True


def _stop(signum, frame):
    global _running
    _running = False


def read_meminfo() -> dict:
    values = {}
    for line in Path("/proc/meminfo").read_text().splitlines():
        key, _, rest = line.partition(":")
        if key in MEMINFO_KEYS:
            values[MEMINFO_KEYS[key]] = int(rest.split()[0])
    total = values.get("mem_total_kb", 0)
    available = values.get("mem_available_kb", 0)
    values["mem_used_kb"] = total - available
    values["swap_used_kb"] = values.get("swap_total_kb", 0) - values.get("swap_free_kb", 0)
    return values


def read_ksm() -> dict:
    def value(name: str) -> int:
        try:
            return int((KSM_ROOT / name).read_text().strip())
        except (OSError, ValueError):
            return 0

    sharing = value("pages_sharing")
    shared = value("pages_shared")
    return {
        "ksm_run": value("run"),
        # pages_sharing counts the pages that were merged away, i.e. the saving
        "ksm_saved_kb": sharing * PAGE_SIZE_KB,
        "ksm_shared_kb": shared * PAGE_SIZE_KB,
        "ksm_unshared_kb": value("pages_unshared") * PAGE_SIZE_KB,
    }


def read_thp_setting() -> str:
    try:
        raw = (Path("/sys/kernel/mm/transparent_hugepage/enabled")).read_text()
    except OSError:
        return "unknown"
    for token in raw.split():
        if token.startswith("[") and token.endswith("]"):
            return token[1:-1]
    return "unknown"


def docker_containers() -> dict:
    """Return {container_id: name} for all running containers."""
    try:
        proc = subprocess.run(
            ["docker", "ps", "--no-trunc", "--format", "{{.ID}}\t{{.Names}}"],
            capture_output=True,
            text=True,
            timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired):
        return {}
    if proc.returncode != 0:
        return {}
    containers = {}
    for line in proc.stdout.splitlines():
        cid, _, name = line.partition("\t")
        if cid and name:
            containers[cid.strip()] = name.strip()
    return containers


def cgroup_dir(cid: str, cache: dict) -> Path | None:
    """Locate the cgroup directory of a container, caching the result."""
    if cid in cache:
        return cache[cid]
    candidates = [
        CGROUP_ROOT / "system.slice" / f"docker-{cid}.scope",
        CGROUP_ROOT / "docker" / cid,
        CGROUP_ROOT / "memory" / "docker" / cid,  # cgroup v1
    ]
    found = next((c for c in candidates if (c / "memory.current").exists()
                  or (c / "memory.usage_in_bytes").exists()), None)
    cache[cid] = found
    return found


def read_container_memory(path: Path) -> dict:
    """Read memory accounting for one cgroup (v2 preferred, v1 fallback)."""
    metrics = {}
    current = path / "memory.current"
    if current.exists():
        try:
            metrics["mem_current_kb"] = int(current.read_text().strip()) // 1024
        except (OSError, ValueError):
            pass
        try:
            for line in (path / "memory.stat").read_text().splitlines():
                key, _, value = line.partition(" ")
                if key in ("anon", "file", "slab", "shmem"):
                    metrics[f"{key}_kb"] = int(value) // 1024
        except (OSError, ValueError):
            pass
        return metrics

    legacy = path / "memory.usage_in_bytes"
    if legacy.exists():
        try:
            metrics["mem_current_kb"] = int(legacy.read_text().strip()) // 1024
        except (OSError, ValueError):
            pass
        try:
            for line in (path / "memory.stat").read_text().splitlines():
                key, _, value = line.partition(" ")
                if key == "rss":
                    metrics["anon_kb"] = int(value) // 1024
                elif key == "cache":
                    metrics["file_kb"] = int(value) // 1024
        except (OSError, ValueError):
            pass
    return metrics


def qemu_rss_by_container() -> dict:
    """Sum the RSS of every qemu process, keyed by its container id."""
    totals = {}
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        try:
            comm = (entry / "comm").read_text().strip()
            if not comm.startswith("qemu-system"):
                continue
            cgroup = (entry / "cgroup").read_text()
            status = (entry / "status").read_text()
        except OSError:
            # process exited between listing and reading
            continue

        cid = None
        for token in cgroup.replace("/", " ").replace(".scope", " ").split():
            if token.startswith("docker-") and len(token) > 20:
                cid = token[len("docker-"):]
                break
        if cid is None:
            continue

        for line in status.splitlines():
            if line.startswith("VmRSS:"):
                totals[cid] = totals.get(cid, 0) + int(line.split()[1])
                break
    return totals


def sample(writer, started_at: float, cgroup_cache: dict, hostname: str) -> None:
    now = time.time()
    elapsed = round(now - started_at, 1)
    ts = round(now, 1)

    def emit(scope, name, metric, value):
        writer.writerow([ts, elapsed, scope, name, metric, value])

    for metric, value in read_meminfo().items():
        emit("host", hostname, metric, value)
    for metric, value in read_ksm().items():
        emit("host", hostname, metric, value)

    containers = docker_containers()
    qemu = qemu_rss_by_container()
    for cid, name in containers.items():
        path = cgroup_dir(cid, cgroup_cache)
        if path is not None:
            for metric, value in read_container_memory(path).items():
                emit("container", name, metric, value)
        if cid in qemu:
            emit("container", name, "qemu_rss_kb", qemu[cid])


def cmd_sample(args: argparse.Namespace) -> int:
    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    started_at = time.time()

    if args.meta:
        meta = {
            "flavor": args.flavor,
            "profile": args.profile,
            "started_at": started_at,
            "interval_s": args.interval,
            "hostname": os.uname().nodename,
            "thp_setting": read_thp_setting(),
            "ksm_run": read_ksm()["ksm_run"],
            "leaf_memory_mb": os.environ.get("MINI_LAB_LEAF_MEMORY", ""),
            "machine_memory_mb": os.environ.get("MINI_LAB_MACHINE_MEMORY", ""),
        }
        meta_path = Path(args.meta)
        meta_path.parent.mkdir(parents=True, exist_ok=True)
        meta_path.write_text(json.dumps(meta, indent=2) + "\n")

    hostname = os.uname().nodename
    cgroup_cache: dict = {}
    with out.open("w", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(["ts", "elapsed_s", "scope", "name", "metric", "value"])
        while _running:
            try:
                sample(writer, started_at, cgroup_cache, hostname)
            except Exception as exc:  # never let a transient read kill the trace
                print(f"memory-trace: sample failed: {exc}", file=sys.stderr)
            fh.flush()
            # sleep in small slices so SIGTERM is honoured promptly
            deadline = time.time() + args.interval
            while _running and time.time() < deadline:
                time.sleep(0.2)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    s = sub.add_parser("sample", help="sample until terminated")
    s.add_argument("--out", required=True, help="CSV trace output path")
    s.add_argument("--meta", help="write run metadata JSON to this path")
    s.add_argument("--interval", type=float, default=5.0, help="seconds between samples")
    s.add_argument("--flavor", default=os.environ.get("MINI_LAB_FLAVOR", ""))
    s.add_argument("--profile", default=os.environ.get("MINI_LAB_MEMORY_PROFILE", ""))
    s.set_defaults(func=cmd_sample)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())

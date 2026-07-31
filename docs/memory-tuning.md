# Memory tuning

The mini-lab runs every leaf and every machine as a QEMU VM inside a
containerlab container. Those VMs dominate the memory footprint of a lab run,
and QEMU RSS behaves as a high-water mark: the guest eventually touches all of
its RAM through the page cache, so a guest started with `-m 4096` ends up
resident at roughly 4 GiB regardless of how much memory it actually needs.

Three knobs are available to reduce that footprint. All of them are **opt-in** —
without the environment variables below, the lab behaves exactly as it did
before they existed.

## Knobs

| variable | default | effect |
| --- | --- | --- |
| `MINI_LAB_LEAF_MEMORY` | `4096` | `QEMU_MEMORY` handed to leaf01/leaf02 (MB) |
| `MINI_LAB_MACHINE_MEMORY` | `2048` | `QEMU_MEMORY` handed to the machine VMs (MB) |
| `MINI_LAB_KSM` | unset | `true`/`false` — kernel samepage merging on the host |
| `MINI_LAB_THP` | unset | `always`/`madvise`/`never` — transparent hugepage policy |

`MINI_LAB_LEAF_MEMORY` and `MINI_LAB_MACHINE_MEMORY` are substituted into the
containerlab topologies and are picked up by all three VM launchers — the SONiC
`launch.py`, the machine `launch.py` and vrnetlab (used by the `dell_sonic`
flavors) all read `QEMU_MEMORY`.

`MINI_LAB_KSM` and `MINI_LAB_THP` are **host global** and need root. They are
applied by `scripts/memory-tuning.sh`, which is run automatically as part of
`make partition-bake` and reverted by `make cleanup`. The previous values are
saved in `.memory-tuning.state` so the host is left as it was found.

### Why these three

* **Guest RAM sizing** is the dominant lever. A SONiC leaf idles at roughly
  2.1 GB of genuinely used guest memory; the remaining GBs of a 4096 MB guest
  become page cache, which pins host RSS without doing useful work.
* **KSM** deduplicates identical guest pages. leaf01/leaf02 boot the same image,
  as do the machine VMs, so there is a lot to merge. QEMU already marks guest
  RAM `MADV_MERGEABLE`, so only the host-side switch is needed. The cost is
  `ksmd` CPU time and some latency jitter from merge/CoW faults.
* **THP=madvise** stops the kernel from backing sparsely touched guest RAM with
  2 MiB pages. The cost is losing hugepage benefits for the dataplane, which
  matters for the VPP flavor.

Note that `virtio-balloon` with `free-page-reporting=on` is already enabled on
the SONiC VMs, but it reclaims very little in practice: the guest page cache
keeps almost nothing on the free lists, and what is free is usually fragmented
below the default reporting order of 9 (2 MiB).

## Profiles

`scripts/memory-profile.sh` bundles the knobs into named profiles. They are
one-factor-at-a-time variations of `baseline` so that each knob can be measured
on its own, plus `all` which combines them.

| profile | leaf MB | machine MB | KSM | THP |
| --- | --- | --- | --- | --- |
| `baseline` | 4096 | 2048 | off | always |
| `low-memory` | 2560 | 1536 | off | always |
| `ksm` | 4096 | 2048 | **on** | always |
| `thp-madvise` | 4096 | 2048 | off | **madvise** |
| `all` | **2560** | **1536** | **on** | **madvise** |

`baseline` pins KSM and THP explicitly rather than leaving them untouched, so
that a comparison is not skewed by whatever the host happened to be set to.

Local use:

```bash
eval "$(make memory-profile PROFILE=low-memory)"
make up
```

or directly:

```bash
eval "$(./scripts/memory-profile.sh all --export)"
make up
```

## Tracing

`scripts/memory-trace.py` samples host and per-container memory into a CSV.
Everything it reads (`/proc`, `/sys/fs/cgroup`) is world readable, so it needs
no privileges even though the QEMU processes belong to root.

```bash
make memory-trace-start     # background sampler, 5s interval
# ... run the lab ...
make memory-trace-stop
make memory-report          # summary.json + summary.md next to the trace
```

Artifacts land in `memory-traces/`:

| file | content |
| --- | --- |
| `trace.csv` | long format samples: `ts,elapsed_s,scope,name,metric,value` |
| `meta.json` | flavor, profile and the effective host settings of the run |
| `summary.json` | machine readable peaks and means |
| `summary.md` | the same as a markdown table with sparklines |

To compare several runs:

```bash
./scripts/memory-report.py compare --input-dir memory-traces
```

## CI

`test/integration.sh` starts the tracer before `make up` and stops it in an
`EXIT` trap, so a summary is produced even when a test fails — a profile that is
too tight for a flavor is a result worth recording.

The integration workflow builds its matrix from flavors × memory profiles and
runs the full 4 × 5 combination on every event, so every pull request produces
on/off data for each knob on every flavor.

`workflow_dispatch` takes `flavors` and `memory_profiles` inputs to narrow that
down, which is what you want while iterating on the lab itself:

```bash
gh workflow run integration.yaml \
  -f flavors=sonic_vpp \
  -f memory_profiles=baseline,all
```

Be aware of the cost: 20 full integration runs that cannot overlap add up to
many hours of self-hosted runner time per pull request.

Runs are serialised (`max-parallel: 1`) because the host level numbers would
otherwise be contaminated by concurrent labs. Every run uploads a
`memory-trace-<flavor>-<profile>` artifact, and a final `memory-comparison` job
downloads them all, renders a per-flavor comparison table into the job summary
and uploads it as the `memory-comparison` artifact.

# Benchmarks

## `staging-bench`: archive staging throughput

`staging-bench` measures how fast `FBArtifactStaging` gets an archive from where it arrives onto disk: fetch, decompress and extract, with no install after it. The numbers belong to the archive pipeline alone, with no `installd`, simulator or gRPC in them.

It measures every combination of:

- **Sources:** `path` (a local file), `stream-64k` and `stream-1m` (in memory, in frames of that size, as a gRPC client streams), `url` (HTTP from a server on the same host), and `pipe` (a kernel pipe written by another thread, as `cat app.ipa | idb2 install -`).
- **Formats:** `ipa-stored`, `ipa-deflated`, `zip-zstd`, `tar-gz` and `tar-zst`. zstd fixtures are compressed with `zstd -3` when one is installed, and otherwise written as stored blocks. Each result records which.
- **Fixtures:** `<megabytes>x<files>`. Holding the size and varying the file count separates per-byte costs from per-file costs. Contents are `compressible` text or seeded `incompressible` bytes.

Each measurement runs in a fresh process and is written as one JSON line with:

- throughput, as the app's extracted megabytes per second, so formats compare on what they deliver;
- CPU seconds, including any `bsdtar` child;
- peak resident memory;
- the extractor routes staging reported.

## Checking a change

Build `staging-bench` at the parent commit and at the change, then measure them against each other on one machine:

```
staging-bench ab --base ./staging-bench-parent --head ./staging-bench-change --output ab.jsonl
```

`ab` alternates the two binaries run by run, so drift in the host's load lands on both, and then compares them. A case **regresses** when the head's median throughput falls, or its median CPU time rises, by more than 5% or by three times the noise (the larger median absolute deviation), whichever is larger. It also regresses when its median peak memory rises by more than 10%, or when it fails more runs. A verdict needs at least five runs a side: a same-binary comparison of two runs a side "regresses" by 15–40%. The thresholds are fixed so that they can't be tuned to a result. `ab` exits 1 on any regression. `compare` re-reads a results file.

`--quick` runs 64 MB fixtures twice each, in a few minutes. It is a smoke test, too noisy for a verdict.

## Nightly

The `Staging benchmark` workflow runs the quick matrix nightly on a hosted runner and keeps the results as an artifact. Hosted runners are too noisy to hold a commit to a few percent, so it fails only when a case fails or its median falls under an order-of-magnitude floor (`floor.py`).

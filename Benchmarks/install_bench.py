#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Benchmark idb app installs over a shaped localhost link.

Everything runs on one Mac: a companion for a simulator, an HTTP server for URL
installs, and an in-process proxy that adds latency, a bandwidth cap and a
receive window in front of both. Nothing leaves localhost, so a link scenario
is identical on every run and every host, and results compare across companion
revisions and across ways of getting an app onto the simulator:

    python3 -m Benchmarks.install_bench run --companion base/idb_companion --idb idb --label base --output /tmp/base.jsonl
    python3 -m Benchmarks.install_bench run --companion top/idb_companion --idb idb --label top --output /tmp/top.jsonl --sizes 400 --file-kib 16,256
    python3 -m Benchmarks.install_bench summarize /tmp/base.jsonl /tmp/top.jsonl

A full run takes hours at 400MB; `run --quick` takes minutes and is the loop
for iterating on a change, with a full run to confirm it.

`run` measures the companion and client it is given, creates and deletes a
throwaway simulator unless --udid is given, and writes one JSON line per install:
its wall time, the companion's documented install columns (receive_ms,
extract_ms, install_ms, ...) read from its completion line, and the companion's
peak resident memory while it ran.

Patterns (what reaches the companion, and how):
  simctl           `simctl install` of the .app, no idb: the floor
  path-app         local companion installs the .app in place
  path-ipa         local companion extracts the .ipa from disk
  stream-ipa       client streams the .ipa (stored zip) with the compression it negotiates
  stream-ipa-raw   client streams the .ipa as raw chunks
  stream-ipa-deflate  the same as stream-ipa with a deflated .ipa
  stream-app       client streams the .app with the compression it negotiates
  stream-gzip      client streams the .app as tar | gzip
  stream-zstd      client streams the .app as tar | zstd
  stream-ipa-readonly  the same as stream-ipa with a read-only .ipa, like a build output
  url-ipa          companion downloads the stored .ipa
  url-tgz          companion downloads a .tar.gz of the .app
  url-tzst         companion downloads a .tar.zst of the .app
  curl-ipa         `curl <url> | idb install -`: the client streams the stored .ipa from a pipe
  curl-tgz         the same with a .tar.gz of the .app

simctl and path-* never touch the link, so they run once per fixture under the
`local` scenario. Holding --sizes fixed while varying --file-kib separates
per-byte costs (transfer, decompression) from per-file costs (extraction,
installd).
"""

from __future__ import annotations

import argparse
import asyncio
import contextlib
import fcntl
import functools
import http.server
import json
import os
import plistlib
import random
import shutil
import signal
import statistics
import subprocess
import sys
import tempfile
import threading
import time
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterator, Sequence

MIB = 1024 * 1024
BUNDLE_ID = "com.facebook.idb.installbench"
COMPANION_READY_TIMEOUT_S = 60.0
COMPLETION_LINE_WAIT_S = 1.0
RSS_SAMPLE_INTERVAL_S = 0.05
PROXY_READ_BYTES = 64 * 1024
# A symlink in every fixture, which an install has to keep: frameworks
# carry them (`Versions/Current`), and flattening one breaks the app.
FIXTURE_LINK = Path("BenchPadding") / "Info.plist"


@dataclass(frozen=True)
class Pattern:
    name: str
    artifact: str  # key into Fixture.artifacts
    route: str  # simctl | path | stream | url | curl
    compression: str | None = None

    @property
    def local(self) -> bool:
        return self.route in ("simctl", "path")


PATTERNS: dict[str, Pattern] = {
    p.name: p
    for p in [
        Pattern("simctl", "app", "simctl"),
        Pattern("path-app", "app", "path"),
        Pattern("path-ipa", "ipa", "path"),
        Pattern("stream-ipa", "ipa", "stream"),
        Pattern("stream-ipa-raw", "ipa", "stream", "GZIP"),
        Pattern("stream-ipa-deflate", "ipa-deflate", "stream"),
        Pattern("stream-app", "app", "stream"),
        Pattern("stream-gzip", "app", "stream", "GZIP"),
        Pattern("stream-zstd", "app", "stream", "ZSTD"),
        Pattern("stream-ipa-readonly", "ipa-readonly", "stream"),
        Pattern("url-ipa", "ipa", "url"),
        Pattern("url-tgz", "tgz", "url"),
        Pattern("url-tzst", "tzst", "url"),
        Pattern("curl-ipa", "ipa", "curl"),
        Pattern("curl-tgz", "tgz", "curl", "GZIP"),
    ]
}


@dataclass(frozen=True)
class Link:
    name: str
    rtt_ms: float
    mbit: float | None
    window_kib: int | None

    @property
    def bytes_per_second(self) -> float | None:
        return None if self.mbit is None else self.mbit * 1_000_000 / 8


# `remote` models a client reaching a remote Mac: ~110ms RTT, where the macOS
# 4 MiB autorcvbufmax caps a single stream near 38 MB/s whatever the NIC.
LINKS: dict[str, Link | None] = {
    "none": None,
    "lan": Link("lan", 1, 1000, 4096),
    "remote": Link("remote", 110, 1000, 4096),
    "remote-slow": Link("remote-slow", 110, 100, 4096),
}


FULL: dict[str, Any] = {
    "sizes": [1, 64, 400],
    "scenarios": ["none", "remote"],
    "iterations": 3,
}
QUICK: dict[str, Any] = {"sizes": [64], "scenarios": ["none"], "iterations": 1}


# --- Link shaping ---------------------------------------------------------


class ShapedProxy:
    """Forward localhost TCP connections through a shaped link.

    Each direction serialises bytes at the link rate, delivers them one-way
    delay later, and only lets `window` bytes be unacknowledged, where an
    acknowledgement takes a further one-way delay to return. That reproduces
    the bandwidth-delay behaviour of a real path, including flow-control
    windows above TCP (HTTP/2), which stay end to end through the proxy.
    """

    def __init__(self, link: Link, upstream_port: int) -> None:
        self.link = link
        self.upstream_port = upstream_port
        self.port = 0
        self._server: asyncio.Server | None = None

    async def start(self) -> int:
        self._server = await asyncio.start_server(self._accept, "127.0.0.1", 0)
        self.port = self._server.sockets[0].getsockname()[1]
        return self.port

    async def stop(self) -> None:
        if self._server is not None:
            self._server.close()
            await self._server.wait_closed()

    async def _accept(
        self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ) -> None:
        try:
            up_reader, up_writer = await asyncio.open_connection(
                "127.0.0.1", self.upstream_port
            )
        except OSError:
            writer.close()
            return
        try:
            await asyncio.gather(
                self._pipe(reader, up_writer), self._pipe(up_reader, writer)
            )
        except OSError:
            pass
        finally:
            for w in (writer, up_writer):
                w.close()

    async def _pipe(
        self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ) -> None:
        loop = asyncio.get_running_loop()
        delay = self.link.rtt_ms / 2000
        rate = self.link.bytes_per_second
        window = None if self.link.window_kib is None else self.link.window_kib * 1024
        queue: asyncio.Queue[tuple[float, bytes] | None] = asyncio.Queue()
        in_flight = 0
        opened = asyncio.Event()

        def acknowledge(count: int) -> None:
            nonlocal in_flight
            in_flight -= count
            opened.set()

        async def deliver() -> None:
            while (item := await queue.get()) is not None:
                due, data = item
                wait = due - loop.time()
                if wait > 0:
                    await asyncio.sleep(wait)
                writer.write(data)
                await writer.drain()
                loop.call_later(delay, acknowledge, len(data))
            if writer.can_write_eof():
                writer.write_eof()

        delivery = asyncio.create_task(deliver())
        transmitted_until = 0.0
        try:
            while data := await reader.read(PROXY_READ_BYTES):
                while (
                    window is not None and in_flight and in_flight + len(data) > window
                ):
                    opened.clear()
                    await opened.wait()
                in_flight += len(data)
                sent = max(loop.time(), transmitted_until)
                if rate is not None:
                    sent += len(data) / rate
                transmitted_until = sent
                queue.put_nowait((sent + delay, data))
        finally:
            queue.put_nowait(None)
            await delivery


# --- Fixtures -------------------------------------------------------------


@dataclass(frozen=True)
class Fixture:
    size_mb: int
    file_kib: int
    compressible: float
    directory: Path
    app: Path
    artifacts: dict[str, Path]

    @property
    def key(self) -> str:
        return self.directory.name


def tree_bytes(path: Path) -> int:
    if path.is_file():
        return path.stat().st_size
    return sum(p.lstat().st_size for p in path.rglob("*") if not p.is_dir())


def _text_block(rng: random.Random, size: int) -> bytes:
    words = [
        "".join(
            rng.choice("abcdefghijklmnopqrstuvwxyz") for _ in range(rng.randint(2, 9))
        )
        for _ in range(2048)
    ]
    out = bytearray()
    while len(out) < size:
        out += " ".join(rng.choices(words, k=512)).encode() + b"\n"
    return bytes(out[:size])


def pad_bundle(app: Path, pad_bytes: int, file_kib: int, compressible: float) -> None:
    """Add deterministic padding files so the bundle reaches a target size.

    `compressible` is the share of each file that is text-like; the rest is
    random, so compressors see a ratio close to a real app's.
    """
    rng = random.Random(0)
    text = _text_block(rng, 4 * MIB)
    directory = app / "BenchPadding"
    directory.mkdir()
    file_bytes = file_kib * 1024
    index = 0
    while pad_bytes > 0:
        size = min(file_bytes, pad_bytes)
        text_bytes = int(size * compressible)
        offset = rng.randrange(0, len(text) - text_bytes + 1)
        subdirectory = directory / f"{index // 256:04d}"
        subdirectory.mkdir(exist_ok=True)
        (subdirectory / f"{index:06d}.bin").write_bytes(
            text[offset : offset + text_bytes] + rng.randbytes(size - text_bytes)
        )
        pad_bytes -= size
        index += 1


def write_ipa(app: Path, destination: Path, compression: int) -> None:
    """Write `Payload/<name>.app` preserving modes and symlinks, like ditto."""
    with zipfile.ZipFile(destination, "w", compression=compression) as archive:
        for path in sorted([app, *app.rglob("*")]):
            name = str(Path("Payload") / path.relative_to(app.parent))
            mode = path.lstat().st_mode
            if path.is_symlink():
                info = zipfile.ZipInfo(name)
                info.external_attr = mode << 16
                archive.writestr(info, os.readlink(path))
            elif path.is_dir():
                info = zipfile.ZipInfo(name + "/")
                info.external_attr = (mode << 16) | 0x10
                archive.writestr(info, b"")
            else:
                archive.write(path, name)


def write_tar(app: Path, destination: Path, compressor: Sequence[str]) -> None:
    with open(destination, "wb") as out:
        tar = subprocess.Popen(
            ["tar", "-C", str(app.parent), "-cf", "-", app.name], stdout=subprocess.PIPE
        )
        subprocess.run(list(compressor), stdin=tar.stdout, stdout=out, check=True)
        if tar.wait() != 0:
            raise RuntimeError(f"tar of {app} failed")


def zstd_binary() -> str | None:
    return shutil.which("pzstd") or shutil.which("zstd")


def build_fixture(
    base_app: Path, cache: Path, size_mb: int, file_kib: int, compressible: float
) -> Fixture:
    key = f"{base_app.stem}-{size_mb}mb-{file_kib}kib-{round(compressible * 100)}c"
    directory = cache / key
    app = directory / "app" / "InstallBench.app"
    artifacts = {
        "app": app,
        "ipa": directory / "stored.ipa",
        "ipa-readonly": directory / "readonly.ipa",
        "ipa-deflate": directory / "deflated.ipa",
        "tgz": directory / "app.tar.gz",
    }
    zstd = zstd_binary()
    if zstd is not None:
        artifacts["tzst"] = directory / "app.tar.zst"
    fixture = Fixture(size_mb, file_kib, compressible, directory, app, artifacts)
    marker = directory / ("complete" if zstd is None else "complete-zstd")
    if (
        marker.exists()
        and all(path.exists() for path in artifacts.values())
        and (app / FIXTURE_LINK).is_symlink()
    ):
        return fixture
    shutil.rmtree(directory, ignore_errors=True)
    app.parent.mkdir(parents=True)
    shutil.copytree(base_app, app, symlinks=True)
    # The base app can be a read-only build output, and copytree keeps its modes.
    subprocess.run(["chmod", "-R", "u+w", str(app)], check=True)
    info_path = app / "Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    info["CFBundleIdentifier"] = BUNDLE_ID
    info_path.write_bytes(plistlib.dumps(info))
    pad_bundle(app, size_mb * MIB - tree_bytes(app), file_kib, compressible)
    (app / FIXTURE_LINK).symlink_to(Path("..") / "Info.plist")
    # Padding and the new identifier break the seal; re-sign so installd accepts it.
    subprocess.run(
        ["codesign", "--force", "--sign", "-", str(app)],
        check=True,
        capture_output=True,
    )
    write_ipa(app, artifacts["ipa"], zipfile.ZIP_STORED)
    shutil.copyfile(artifacts["ipa"], artifacts["ipa-readonly"])
    artifacts["ipa-readonly"].chmod(0o444)
    write_ipa(app, artifacts["ipa-deflate"], zipfile.ZIP_DEFLATED)
    write_tar(app, artifacts["tgz"], ["gzip", "-6"])
    if zstd is not None:
        write_tar(app, artifacts["tzst"], [zstd, "-3", "-c"])
    marker.touch()
    return fixture


# --- Simulator, companion and HTTP server ---------------------------------


def simctl(device_set: Path | None) -> list[str]:
    return ["xcrun", "simctl", *(["--set", str(device_set)] if device_set else [])]


@contextlib.contextmanager
def exclusive(udid: str) -> Iterator[None]:
    """Hold the simulator for this run: another run's installs would skew both."""
    path = Path(tempfile.gettempdir()) / f"idb-install-bench-{udid}.lock"
    with open(path, "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise SystemExit(f"another install bench is using simulator {udid}")
        yield


@contextlib.contextmanager
def simulator(udid: str | None, device_set: Path | None) -> Iterator[str]:
    """Yield a booted simulator, creating and deleting one unless given."""
    if udid is not None:
        yield udid
        return
    runtimes = json.loads(
        subprocess.run(
            [*simctl(device_set), "list", "-j", "runtimes"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout
    )["runtimes"]
    ios = [r for r in runtimes if r.get("platform") == "iOS" and r.get("isAvailable")]
    if not ios:
        raise SystemExit("no available iOS simulator runtime")
    runtime = max(ios, key=lambda r: [int(p) for p in r["version"].split(".")])
    device_type = next(
        d["identifier"]
        for d in runtime["supportedDeviceTypes"]
        if d.get("productFamily") == "iPhone"
    )
    created = subprocess.run(
        [
            *simctl(device_set),
            "create",
            "idb-install-bench",
            device_type,
            runtime["identifier"],
        ],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    try:
        subprocess.run(
            [*simctl(device_set), "bootstatus", created, "-b"],
            check=True,
            capture_output=True,
        )
        yield created
    finally:
        subprocess.run([*simctl(device_set), "shutdown", created], capture_output=True)
        subprocess.run([*simctl(device_set), "delete", created], capture_output=True)


class Companion:
    def __init__(
        self, path: Path, udid: str, device_set: Path | None, directory: Path
    ) -> None:
        self.log_path = directory / "companion.log"
        self.process = subprocess.Popen(
            [
                str(path),
                "--udid",
                udid,
                *(["--device-set-path", str(device_set)] if device_set else []),
                "--grpc-port",
                "0",
                "--log-file-path",
                str(self.log_path),
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            stdin=subprocess.DEVNULL,
            start_new_session=True,
            text=True,
        )
        try:
            self.port: int = self._wait_until_ready()
        except BaseException:
            self.stop()
            raise

    @contextlib.contextmanager
    def peak_rss(self) -> Iterator[RSSSampler]:
        """Samples the companion's resident memory while the block runs."""
        sampler = RSSSampler(self.process.pid)
        sampler.start()
        try:
            yield sampler
        finally:
            sampler.stop()

    def _wait_until_ready(self) -> int:
        # The companion binds `--grpc-port 0` itself and reports the port it got,
        # so no other process can take the port between choosing and binding it.
        assert self.process.stdout is not None
        deadline = time.monotonic() + COMPANION_READY_TIMEOUT_S
        while time.monotonic() < deadline:
            line = self.process.stdout.readline()
            if not line and self.process.poll() is not None:
                break
            with contextlib.suppress(ValueError):
                report = json.loads(line)
                if isinstance(report, dict) and "grpc_port" in report:
                    return int(report["grpc_port"])
        raise RuntimeError(
            f"the companion did not become ready; log: {self.log_excerpt()}"
        )

    def log_excerpt(self, limit: int = 2000) -> str:
        try:
            return self.log_path.read_text(errors="replace")[-limit:]
        except OSError:
            return "<no log>"

    def completion_lines(self) -> list[str]:
        try:
            log = self.log_path.read_text(errors="replace")
        except OSError:
            return []
        return [line for line in log.splitlines() if "payload_kind=" in line]

    def stop(self) -> None:
        with contextlib.suppress(ProcessLookupError):
            os.killpg(self.process.pid, signal.SIGTERM)
        try:
            self.process.wait(timeout=15)
        except subprocess.TimeoutExpired:
            with contextlib.suppress(ProcessLookupError):
                os.killpg(self.process.pid, signal.SIGKILL)
            self.process.wait()


class RSSSampler:
    """The highest resident memory a process reaches while sampled, every `RSS_SAMPLE_INTERVAL_S`."""

    def __init__(self, pid: int) -> None:
        self.pid = pid
        # None until a sample is taken, so a process never sampled reports no peak rather than a peak of nothing.
        self.peak_kb: int | None = None
        self._stopped = threading.Event()
        self._thread = threading.Thread(target=self._sample, daemon=True)

    def start(self) -> None:
        self._thread.start()

    def stop(self) -> None:
        self._stopped.set()
        self._thread.join()
        self._record()

    def _sample(self) -> None:
        while not self._stopped.wait(RSS_SAMPLE_INTERVAL_S):
            self._record()

    def _record(self) -> None:
        if (kb := rss_kb(self.pid)) is not None:
            self.peak_kb = kb if self.peak_kb is None else max(self.peak_kb, kb)


def rss_kb(pid: int) -> int | None:
    """A process's resident memory in KiB, as `ps` reports it, or None once it has gone or `ps` can't be run, as in
    sandboxes that forbid it."""
    try:
        shown = subprocess.run(
            ["ps", "-o", "rss=", "-p", str(pid)], capture_output=True, text=True
        )
        return int(shown.stdout.strip())
    except (OSError, ValueError):
        return None


def completion_columns(line: str) -> dict[str, str]:
    """Columns from a companion install completion line's `{k=v, ...}` suffix."""
    if not line.rstrip().endswith("}") or "{" not in line:
        return {}
    body = line.rsplit("{", 1)[1].rstrip().rstrip("}")
    return dict(column.split("=", 1) for column in body.split(", ") if "=" in column)


@contextlib.contextmanager
def http_server(directory: Path) -> Iterator[int]:
    class Handler(http.server.SimpleHTTPRequestHandler):
        def log_message(self, format: str, *args: Any) -> None:
            pass

    server = http.server.ThreadingHTTPServer(
        ("127.0.0.1", 0), functools.partial(Handler, directory=str(directory))
    )
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield server.server_address[1]
    finally:
        server.shutdown()
        server.server_close()


# --- Running installs -----------------------------------------------------


@dataclass
class Bench:
    label: str
    idb: Path
    companion: Companion
    udid: str
    device_set: Path | None
    cache: Path
    http_port: int
    deadline_s: float

    async def install(
        self,
        pattern: Pattern,
        fixture: Fixture,
        scenario: str,
        companion_port: int,
        http_port: int,
        iteration: int,
    ) -> dict[str, Any]:
        artifact = fixture.artifacts[pattern.artifact]
        await self._run([*simctl(self.device_set), "uninstall", self.udid, BUNDLE_ID])
        env = {k: v for k, v in os.environ.items() if k != "IDB_FORCE_REMOTE"}
        url = f"http://127.0.0.1:{http_port}/{artifact.relative_to(self.cache)}"
        if pattern.route == "stream":
            env["IDB_FORCE_REMOTE"] = "1"
        argv = install_argv(
            pattern,
            self.idb,
            companion_port,
            url if pattern.route in ("url", "curl") else str(artifact),
            [*simctl(self.device_set), "install", self.udid],
        )
        earlier = len(self.companion.completion_lines())
        with self.companion.peak_rss() as rss:
            start = time.monotonic()
            returncode, stderr = await self._run(argv, env=env, timeout=self.deadline_s)
            wall_s = time.monotonic() - start
        outcome = (
            "timeout" if returncode is None else "ok" if returncode == 0 else "failed"
        )
        if outcome == "ok" and (mismatch := self.installed_mismatch()) is not None:
            outcome, stderr = "mismatch", mismatch
        columns: dict[str, str] = {}
        if pattern.route != "simctl":
            waited_until = time.monotonic() + COMPLETION_LINE_WAIT_S
            while time.monotonic() < waited_until:
                lines = self.companion.completion_lines()[earlier:]
                if lines:
                    columns = completion_columns(lines[0])
                    break
                await asyncio.sleep(0.05)
        return {
            "label": self.label,
            "scenario": scenario,
            "pattern": pattern.name,
            "fixture": fixture.key,
            "size_mb": fixture.size_mb,
            "file_kib": fixture.file_kib,
            "artifact_bytes": tree_bytes(artifact),
            "iteration": iteration,
            "outcome": outcome,
            "wall_s": round(wall_s, 3),
            "error": None if outcome == "ok" else stderr[-800:],
            "columns": columns,
            # simctl installs without the companion, so it has nothing to report.
            "companion_peak_rss_kb": None if pattern.route == "simctl" else rss.peak_kb,
        }

    def installed_mismatch(self) -> str | None:
        """How the installed app differs from the fixture, if it does."""
        container = subprocess.run(
            [*simctl(self.device_set), "get_app_container", self.udid, BUNDLE_ID],
            capture_output=True,
            text=True,
        )
        if container.returncode != 0:
            return f"the app is not installed: {container.stderr.strip()}"
        if not (Path(container.stdout.strip()) / FIXTURE_LINK).is_symlink():
            return f"{FIXTURE_LINK} was not installed as a symlink"
        return None

    @staticmethod
    async def _run(
        argv: Sequence[str], env: dict[str, str] | None = None, timeout: float = 60
    ) -> tuple[int | None, str]:
        process = await asyncio.create_subprocess_exec(
            *argv,
            env=env,
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.PIPE,
            start_new_session=True,
        )
        try:
            _, stderr = await asyncio.wait_for(process.communicate(), timeout)
        except TimeoutError:
            # Like a caller's deadline: the client is killed, not asked to stop.
            with contextlib.suppress(ProcessLookupError):
                os.killpg(process.pid, signal.SIGKILL)
            await process.wait()
            return None, f"killed after the {timeout:.0f}s deadline"
        return process.returncode, stderr.decode(errors="replace")


def install_argv(
    pattern: Pattern,
    idb: Path,
    companion_port: int,
    target: str,
    simctl_install: Sequence[str],
) -> list[str]:
    if pattern.route == "simctl":
        return [*simctl_install, target]
    client = [
        str(idb),
        "--companion",
        f"127.0.0.1:{companion_port}",
        *(["--compression", pattern.compression] if pattern.compression else []),
        "install",
        "--json",
    ]
    if pattern.route != "curl":
        return [*client, target]
    # pipefail so that a failed download fails the install, not just truncates it. bash, not
    # sh: where sh is dash, as on Ubuntu, `set -o pipefail` is rejected before curl runs.
    return [
        "bash",
        "-c",
        'set -o pipefail; curl -sfS "$0" | "$@"',
        target,
        *client,
        "-",
    ]


def progress(record: dict[str, Any]) -> str:
    phases = " ".join(
        f"{k}={v}" for k, v in record["columns"].items() if k.endswith("_ms")
    )
    return (
        f"{record['fixture']} {record['scenario']:<11} {record['pattern']:<18} "
        f"#{record['iteration']} {record['outcome']:<7} {record['wall_s']:7.2f}s {phases}"
    )


async def run_matrix(
    bench: Bench,
    fixtures: Sequence[Fixture],
    scenarios: Sequence[str],
    patterns: Sequence[Pattern],
    iterations: int,
    output: Any,
) -> list[dict[str, Any]]:
    direct = (bench.companion.port, bench.http_port)
    proxies: dict[str, tuple[int, int]] = {"none": direct, "local": direct}
    started: list[ShapedProxy] = []
    for scenario in scenarios:
        link = LINKS[scenario]
        if link is None:
            continue
        grpc = ShapedProxy(link, bench.companion.port)
        http = ShapedProxy(link, bench.http_port)
        started += [grpc, http]
        proxies[scenario] = (await grpc.start(), await http.start())
    runs = [("local", p) for p in patterns if p.local] + [
        (s, p) for s in scenarios for p in patterns if not p.local
    ]
    # A fresh simulator's first installs, and the client's first launch, run
    # several times slower than later ones; pay for them before measuring.
    warm = fixtures[0]
    for pattern in (PATTERNS["simctl"], PATTERNS["path-ipa"], PATTERNS["stream-ipa"]):
        await bench.install(pattern, warm, "none", *proxies["none"], -1)
    records = []
    try:
        # Iterations are the outer loop so that drift on the host (Spotlight,
        # a simulator settling after boot) spreads across patterns evenly.
        for iteration in range(iterations):
            for fixture in fixtures:
                for scenario, pattern in runs:
                    if pattern.artifact not in fixture.artifacts:
                        continue
                    record = await bench.install(
                        pattern, fixture, scenario, *proxies[scenario], iteration
                    )
                    records.append(record)
                    output.write(json.dumps(record) + "\n")
                    output.flush()
                    print(progress(record), file=sys.stderr)
    finally:
        for proxy in started:
            await proxy.stop()
    return records


# --- Summaries ------------------------------------------------------------


def percentile(values: Sequence[float], q: float) -> float:
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    position = (len(ordered) - 1) * q
    lower = int(position)
    upper = min(lower + 1, len(ordered) - 1)
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (position - lower)


def summarize(records: Sequence[dict[str, Any]]) -> str:
    groups: dict[tuple[Any, ...], list[dict[str, Any]]] = {}
    for record in records:
        key = (
            record["fixture"],
            record["scenario"],
            record["pattern"],
            record["label"],
        )
        groups.setdefault(key, []).append(record)
    header = (
        f"{'fixture':<34} {'scenario':<11} {'pattern':<18} {'label':<10} "
        f"{'n':>3} {'fail':>4} {'p50 s':>7} {'p90 s':>7} {'MB/s':>7} "
        f"{'recv ms':>8} {'extr ms':>8} {'inst ms':>8} {'peak MB':>8}"
    )
    rows = [header, "-" * len(header)]
    for (fixture, scenario, pattern, label), group in sorted(groups.items()):
        ok = [r for r in group if r["outcome"] == "ok"]
        walls = [r["wall_s"] for r in ok]
        p50 = percentile(walls, 0.5) if walls else float("nan")
        p90 = percentile(walls, 0.9) if walls else float("nan")
        rate = group[0]["artifact_bytes"] / 1e6 / p50 if walls and p50 else float("nan")

        def column(name: str, ok: list[dict[str, Any]] = ok) -> str:
            values = [int(r["columns"][name]) for r in ok if name in r["columns"]]
            return f"{statistics.median(values):8.0f}" if values else f"{'-':>8}"

        peaks = [
            r["companion_peak_rss_kb"] / 1024
            for r in ok
            if r.get("companion_peak_rss_kb")
        ]
        peak = f"{statistics.median(peaks):8.0f}" if peaks else f"{'-':>8}"

        rows.append(
            f"{fixture:<34} {scenario:<11} {pattern:<18} {label:<10} "
            f"{len(group):>3} {len(group) - len(ok):>4} {p50:>7.2f} {p90:>7.2f} {rate:>7.1f} "
            f"{column('receive_ms')} {column('extract_ms')} {column('install_ms')} {peak}"
        )
    return "\n".join(rows)


# --- CLI ------------------------------------------------------------------


def positive_int(value: str) -> int:
    number = int(value)
    if number <= 0:
        raise argparse.ArgumentTypeError(f"{value} is not a positive integer")
    return number


def csv(kind: type, choices: Sequence[str] | None = None):  # noqa: ANN201
    def parse(value: str) -> list[Any]:
        items = [kind(v) for v in value.split(",") if v]
        if choices is not None:
            unknown = [v for v in items if v not in choices]
            if unknown:
                raise argparse.ArgumentTypeError(
                    f"unknown {unknown}; choose from {list(choices)}"
                )
        return items

    return parse


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    commands = parser.add_subparsers(dest="command", required=True)
    run = commands.add_parser("run", help="run the install matrix")
    run.add_argument("--label", default="run", help="names this companion in results")
    run.add_argument(
        "--output", type=Path, help="JSONL results (default: a new /tmp file)"
    )
    run.add_argument(
        "--companion",
        type=Path,
        required=True,
        help="idb_companion in a distribution, with Resources/ beside it",
    )
    run.add_argument("--idb", type=Path, required=True, help="the idb client")
    run.add_argument("--udid", help="booted simulator to use (default: create one)")
    run.add_argument("--device-set", type=Path, help="device set --udid lives in")
    run.add_argument(
        "--base-app",
        type=Path,
        help="app to pad (default: the companion's ReplHost.app)",
    )
    run.add_argument(
        "--quick",
        action="store_true",
        help=f"defaults for iterating in minutes rather than hours: {QUICK}",
    )
    run.add_argument(
        "--sizes", type=csv(positive_int), help="app sizes in MB (default: 1,64,400)"
    )
    run.add_argument(
        "--file-kib",
        type=csv(positive_int),
        default=[64],
        help="padding file sizes in KiB",
    )
    run.add_argument(
        "--compressible", type=float, default=0.6, help="text share of padding"
    )
    run.add_argument(
        "--scenarios", type=csv(str, list(LINKS)), help="(default: none,remote)"
    )
    run.add_argument(
        "--patterns", type=csv(str, list(PATTERNS)), default=list(PATTERNS)
    )
    run.add_argument("--iterations", type=int, help="(default: 3)")
    run.add_argument(
        "--deadline", type=float, default=120, help="seconds before a client is killed"
    )
    run.add_argument(
        "--rtt-ms", type=float, help="adds a `custom` scenario with this RTT"
    )
    run.add_argument("--mbit", type=float, help="bandwidth of the custom scenario")
    run.add_argument(
        "--window-kib", type=int, default=4096, help="window of the custom scenario"
    )
    run.add_argument(
        "--cache",
        type=Path,
        default=Path(tempfile.gettempdir()) / "idb-install-bench",
        help="fixture cache, reused across runs",
    )
    summary = commands.add_parser(
        "summarize", help="tabulate one or more JSONL results"
    )
    summary.add_argument("results", type=Path, nargs="+")
    args = parser.parse_args(argv)

    if args.command == "summarize":
        records = [
            json.loads(line)
            for path in args.results
            for line in path.read_text().splitlines()
            if line.strip()
        ]
        print(summarize(records))
        return 0

    for name, value in (QUICK if args.quick else FULL).items():
        if getattr(args, name) is None:
            setattr(args, name, value)
    scenarios = list(args.scenarios)
    if args.rtt_ms is not None:
        LINKS["custom"] = Link("custom", args.rtt_ms, args.mbit, args.window_kib)
        scenarios.append("custom")
    companion_path = args.companion
    idb = args.idb
    base_app = args.base_app or companion_path.parent / "Resources" / "ReplHost.app"
    args.cache.mkdir(parents=True, exist_ok=True)
    if zstd_binary() is None:
        print("no zstd or pzstd on PATH: skipping url-tzst", file=sys.stderr)
    fixtures = [
        build_fixture(base_app, args.cache, size, file_kib, args.compressible)
        for size in args.sizes
        for file_kib in args.file_kib
    ]
    output_path = args.output or Path(
        tempfile.mkstemp(prefix="idb-install-bench-", suffix=".jsonl")[1]
    )
    work = Path(tempfile.mkdtemp(prefix="idb-install-bench-"))
    # Unwinds on a kill, as on an error, so the companion is not left behind.
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(128 + signal.SIGTERM))
    with (
        simulator(args.udid, args.device_set) as udid,
        exclusive(udid),
        http_server(args.cache) as http_port,
    ):
        companion = Companion(companion_path, udid, args.device_set, work)
        try:
            bench = Bench(
                args.label,
                idb,
                companion,
                udid,
                args.device_set,
                args.cache,
                http_port,
                args.deadline,
            )
            with open(output_path, "a") as output:
                records = asyncio.run(
                    run_matrix(
                        bench,
                        fixtures,
                        scenarios,
                        [PATTERNS[name] for name in args.patterns],
                        args.iterations,
                        output,
                    )
                )
        finally:
            companion.stop()
    print(summarize(records))
    print(
        f"\nresults: {output_path}\ncompanion log: {companion.log_path}",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

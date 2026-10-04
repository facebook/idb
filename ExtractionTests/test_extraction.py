# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Install every artifact kind through every route and compare what the companion stores.

A companion targeting the Mac stores what it installs under its auxiliary
directory, so the extracted tree can be compared with the fixture it came from
without a simulator. The caller supplies IDB_BIN and IDB_E2E_COMPANION_PATH.
"""

from __future__ import annotations

import contextlib
import enum
import functools
import http.server
import json
import os
import select
import shutil
import signal
import subprocess
import tempfile
import threading
import time
import unittest
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterator

from .fixtures import Archive, archive, build, describe, differences, Kind

COMPANION_READY_TIMEOUT_SECONDS = 60.0
INSTALL_TIMEOUT_SECONDS = 180.0


class Delivery(enum.Enum):
    PATH = "path"  # the companion reads the client's file in place
    STREAM = "stream"  # the client streams the file, or a tar of the bundle
    URL = "url"  # the companion downloads it
    STDIN = "stdin"  # the client streams its stdin as it arrives


@dataclass(frozen=True)
class Route:
    name: str
    archive: Archive
    delivery: Delivery
    compression: str | None = None


APP_ROUTES: list[Route] = [
    Route("path_app", Archive.NONE, Delivery.PATH),
    Route("path_ipa_stored", Archive.IPA_STORED, Delivery.PATH),
    Route("path_ipa_deflated", Archive.IPA_DEFLATED, Delivery.PATH),
    Route("path_ipa_ditto", Archive.IPA_DITTO, Delivery.PATH),
    Route("stream_app", Archive.NONE, Delivery.STREAM),
    Route("stream_app_gzip", Archive.NONE, Delivery.STREAM, "GZIP"),
    Route("stream_app_zstd", Archive.NONE, Delivery.STREAM, "ZSTD"),
    Route("stream_ipa_stored", Archive.IPA_STORED, Delivery.STREAM),
    Route("stream_ipa_deflated", Archive.IPA_DEFLATED, Delivery.STREAM),
    Route("stream_ipa_ditto", Archive.IPA_DITTO, Delivery.STREAM),
    Route("stream_ipa_gzip", Archive.IPA_DEFLATED, Delivery.STREAM, "GZIP"),
    Route("stream_ipa_zstd", Archive.IPA_DEFLATED, Delivery.STREAM, "ZSTD"),
    Route("url_ipa", Archive.IPA_DEFLATED, Delivery.URL),
    Route("url_tgz", Archive.TGZ, Delivery.URL),
    Route("url_tzst", Archive.TZST, Delivery.URL),
    Route("stdin_ipa", Archive.IPA_DEFLATED, Delivery.STDIN),
    Route("stdin_tgz", Archive.TGZ, Delivery.STDIN, "GZIP"),
    Route("stdin_tzst", Archive.TZST, Delivery.STDIN, "ZSTD"),
    Route("stdin_tgz_declared_zstd", Archive.TGZ, Delivery.STDIN, "ZSTD"),
]

BUNDLE_ROUTES: list[Route] = [
    Route("path", Archive.NONE, Delivery.PATH),
    Route("stream", Archive.NONE, Delivery.STREAM),
    Route("stream_gzip", Archive.NONE, Delivery.STREAM, "GZIP"),
    Route("stream_zstd", Archive.NONE, Delivery.STREAM, "ZSTD"),
]

DYLIB_ROUTES: list[Route] = [
    Route("path", Archive.NONE, Delivery.PATH),
    Route("stream", Archive.NONE, Delivery.STREAM),
]

REPL_HOST_ROUTES: list[Route] = [
    route
    for route in APP_ROUTES
    if route.name in ("path_app", "stream_app", "stream_ipa_deflated", "url_tgz")
]

# Cases that fail today, by test name, with what goes wrong. Each still runs, as
# an expected failure, so a fix shows up as an unexpected success.
KNOWN_BROKEN: dict[str, str] = {
    "test_dylib_stream": "the companion rejects the name hint the client sends before the payload",
    "test_framework_path": "the companion expects a directory holding one bundle, not the bundle itself",
    "test_framework_stream": "stored as a symlink into the extraction directory, which is then deleted",
    "test_framework_stream_gzip": "stored as a symlink into the extraction directory, which is then deleted",
    "test_framework_stream_zstd": "stored as a symlink into the extraction directory, which is then deleted",
}


def _required_binary(name: str) -> Path:
    value = os.environ.get(name)
    if not value:
        raise unittest.SkipTest(f"{name} is not set")
    path = Path(value)
    if not os.access(path, os.X_OK):
        raise RuntimeError(f"{name}={path} is not executable")
    return path


class Companion:
    """A companion targeting the Mac, storing installs in its own directory."""

    def __init__(self, path: Path, directory: Path) -> None:
        # Use /tmp to stay within the Unix socket path limit on macOS.
        self.socket = Path(tempfile.mkdtemp(prefix="idb-x-", dir="/tmp")) / "c.sock"
        self.auxiliary = directory / "auxiliary"
        self.log_path = directory / "companion.log"
        self.process = subprocess.Popen(
            [
                str(path),
                "--udid",
                "mac",
                "--grpc-domain-sock",
                str(self.socket),
                "--log-file-path",
                str(self.log_path),
            ],
            env={**os.environ, "IDB_MAC_AUXILLIARY_DIR": str(self.auxiliary)},
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            stdin=subprocess.DEVNULL,
            start_new_session=True,
        )
        try:
            self._wait_until_ready()
        except BaseException:
            self.stop()
            raise

    def _wait_until_ready(self) -> None:
        stdout = self.process.stdout
        assert stdout is not None
        deadline = time.monotonic() + COMPANION_READY_TIMEOUT_SECONDS
        while (remaining := deadline - time.monotonic()) > 0:
            if self.process.poll() is not None:
                raise RuntimeError(
                    f"The companion exited with {self.process.returncode}: {self.log()}"
                )
            ready, _, _ = select.select([stdout], [], [], min(remaining, 0.2))
            if not ready:
                continue
            with contextlib.suppress(ValueError):
                if "grpc_path" in json.loads(stdout.readline()):
                    return
        raise RuntimeError(
            f"The companion was not ready in {COMPANION_READY_TIMEOUT_SECONDS:.0f}s: {self.log()}"
        )

    def stored(self, kind: Kind, name: str) -> Path:
        """The one stored entry called `name`, wherever the kind's storage nests it."""
        found = list(self.auxiliary.glob(f"idb-mac-aux/*/{kind.storage}/**/{name}"))
        if len(found) != 1:
            raise AssertionError(f"Expected one stored {name}, found {found}")
        return found[0].resolve() if found[0].is_symlink() else found[0]

    def log(self, limit: int = 4000) -> str:
        try:
            return self.log_path.read_text(errors="replace")[-limit:]
        except OSError:
            return "<no companion log>"

    def stop(self) -> None:
        with contextlib.suppress(ProcessLookupError):
            os.killpg(self.process.pid, signal.SIGTERM)
        try:
            self.process.wait(timeout=15)
        except subprocess.TimeoutExpired:
            with contextlib.suppress(ProcessLookupError):
                os.killpg(self.process.pid, signal.SIGKILL)
            self.process.wait()
        if self.process.stdout is not None:
            self.process.stdout.close()
        shutil.rmtree(self.socket.parent, ignore_errors=True)


@contextlib.contextmanager
def http_server(directory: Path) -> Iterator[int]:
    class Handler(http.server.SimpleHTTPRequestHandler):
        def log_message(self, format: str, *args: object) -> None:
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


class ExtractionTests(unittest.TestCase):
    """Each case installs one fixture through one route on its own companion."""

    def setUp(self) -> None:
        self.idb = _required_binary("IDB_BIN")
        self.companion_path = _required_binary("IDB_E2E_COMPANION_PATH")
        directory = tempfile.TemporaryDirectory(prefix="idb-extraction-")
        self.addCleanup(directory.cleanup)
        self.directory = Path(directory.name)
        self.companion = Companion(self.companion_path, self.directory)
        self.addCleanup(self.companion.stop)

    def install(self, kind: Kind, fixture: Path, route: Route) -> None:
        archives = self.directory / "archives"
        archives.mkdir()
        artifact = archive(fixture, route.archive, archives)
        env = {
            key: value for key, value in os.environ.items() if key != "IDB_FORCE_REMOTE"
        }
        if route.delivery in (Delivery.STREAM, Delivery.STDIN):
            env["IDB_FORCE_REMOTE"] = "1"
        argv = [
            str(self.idb),
            "--companion",
            str(self.companion.socket),
            *(["--compression", route.compression] if route.compression else []),
            *kind.subcommand,
        ]
        with contextlib.ExitStack() as stack:
            stdin = subprocess.DEVNULL
            match route.delivery:
                case Delivery.PATH | Delivery.STREAM:
                    argv.append(str(artifact))
                case Delivery.URL:
                    port = stack.enter_context(http_server(archives))
                    argv.append(f"http://127.0.0.1:{port}/{artifact.name}")
                case Delivery.STDIN:
                    stdin = stack.enter_context(artifact.open("rb"))
                    argv.append("-")
            completed = subprocess.run(
                argv,
                env=env,
                stdin=stdin,
                capture_output=True,
                timeout=INSTALL_TIMEOUT_SECONDS,
            )
        if completed.returncode != 0:
            self.fail(
                f"{' '.join(argv)} exited with {completed.returncode}\n"
                f"stderr: {completed.stderr.decode(errors='replace')[-2000:]}\n"
                f"companion log: {self.companion.log()}"
            )

    def check(self, kind: Kind, fixture: Path, route: Route) -> None:
        expected = describe(fixture) if fixture.is_dir() else None
        self.install(kind, fixture, route)
        stored = self.companion.stored(kind, fixture.name)
        if expected is None:
            self.assertEqual(stored.read_bytes(), fixture.read_bytes())
            return
        self.assertEqual(differences(expected, describe(stored)), [])


def _generated(kind: Kind, route: Route) -> Callable[[ExtractionTests], None]:
    def test(self: ExtractionTests) -> None:
        bundle_id = f"com.example.extraction.{kind.name.lower()}"
        self.check(kind, build(kind, self.directory / "fixture", bundle_id), route)

    return test


def _repl_host(route: Route) -> Callable[[ExtractionTests], None]:
    def test(self: ExtractionTests) -> None:
        source = self.companion_path.parent / "Resources" / "ReplHost.app"
        if not source.is_dir():
            self.skipTest(f"{source} is not built")
        fixture = self.directory / "fixture" / source.name
        shutil.copytree(source, fixture, symlinks=True)
        self.check(Kind.APP, fixture, route)

    return test


def _cases() -> dict[str, Callable[[ExtractionTests], None]]:
    routes = {
        Kind.APP: APP_ROUTES,
        Kind.XCTEST: BUNDLE_ROUTES,
        Kind.FRAMEWORK: BUNDLE_ROUTES,
        Kind.DSYM: BUNDLE_ROUTES,
        Kind.DYLIB: DYLIB_ROUTES,
    }
    cases = {
        f"test_{kind.name.lower()}_{route.name}": _generated(kind, route)
        for kind, kind_routes in routes.items()
        for route in kind_routes
    }
    cases |= {
        f"test_repl_host_{route.name}": _repl_host(route) for route in REPL_HOST_ROUTES
    }
    return {
        name: unittest.expectedFailure(test) if name in KNOWN_BROKEN else test
        for name, test in cases.items()
    }


for _name, _test in _cases().items():
    setattr(ExtractionTests, _name, _test)

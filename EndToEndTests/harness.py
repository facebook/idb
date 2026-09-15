# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Run idb commands through one shared companion against a booted simulator.

The caller supplies DEVICE_UDID, DEVICE_SET_PATH, IDB_BIN,
IDB_E2E_COMPANION_PATH and IDB_E2E_RECORDER_PATH. The harness starts the companion
and waits for accessibility readiness; it does not manage the simulator lifecycle.
"""

from __future__ import annotations

import asyncio
import atexit
import enum
import json
import logging
import os
import re
import select
import shlex
import shutil
import signal
import subprocess
import tempfile
import time
import unittest
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Awaitable, Callable, NoReturn, TypeVar

from .recording import Recording

DEVICE_UDID_ENV = "DEVICE_UDID"
DEVICE_SET_PATH_ENV = "DEVICE_SET_PATH"
IDB_BIN_ENV = "IDB_BIN"
IDB_ARGS_ENV = "IDB_ARGS"
IDB_E2E_COMPANION_PATH_ENV = "IDB_E2E_COMPANION_PATH"
IDB_SETUP_BIN_ENV = "IDB_SETUP_BIN"
READ_ONLY_CLIENT_ENV = "IDB_E2E_READ_ONLY_CLIENT"
IDB_E2E_RECORDER_PATH_ENV = "IDB_E2E_RECORDER_PATH"
STRICT_ENV = "IDB_E2E_STRICT"
ARTIFACTS_ENV = "IDB_E2E_ARTIFACTS_DIR"

T = TypeVar("T")

_LOGGER: logging.Logger = logging.getLogger(__name__)

# ReplHost.app ships with the companion, so installation tests need no extra app.
FIXTURE_APP_NAME = "ReplHost.app"
FIXTURE_APP_BUNDLE_ID = "com.facebook.idb.replhost"

# Hosts without SimLaunchHostService cannot spawn simulator processes.
HOST_SERVICE_UNAVAILABLE_MARKERS = (
    "SimLaunchHostService.RequestError",
    "Exit Code 149 is not acceptable",
)

# Match the connection error emitted by idb/grpc/client.py.
COMPANION_UNREACHABLE_MARKERS = ("Failed to connect to companion",)

# This accessibility error is retryable while the simulator starts.
ACCESSIBILITY_NOT_READY_MARKER = "No translation object returned"
ACCESSIBILITY_PROBE_ARGS = ("ui", "describe-all", "--json")

POLL_INTERVAL_SECONDS = 1.0

COMPANION_READY_TIMEOUT_SECONDS = 180.0
ACCESSIBILITY_READY_TIMEOUT_SECONDS = 180.0
DEFAULT_COMMAND_TIMEOUT_SECONDS = 120.0
INSTALL_TIMEOUT_SECONDS = 300.0


class HarnessError(Exception):
    """Test setup or a harness operation failed."""


class CompanionDied(HarnessError):
    """The shared companion exited; stop the remaining tests."""


class NotReady(Exception):
    """Retry this poll because the expected condition is not met yet."""


class Deadline:
    """Track elapsed time using a monotonic clock."""

    def __init__(self, seconds: float) -> None:
        self.seconds = seconds
        self._at = time.monotonic() + seconds

    @property
    def remaining(self) -> float:
        return self._at - time.monotonic()

    @property
    def passed(self) -> bool:
        return self.remaining <= 0


async def wait_until(what: str, timeout: float, poll: Callable[[], Awaitable[T]]) -> T:
    """Retry on NotReady until the timeout; propagate other exceptions.

    The timeout is checked between polls. Each poll must bound its own runtime.
    """
    deadline = Deadline(timeout)
    while True:
        try:
            return await poll()
        except NotReady as not_ready:
            if deadline.passed:
                raise HarnessError(
                    f"{what} within {timeout:.0f}s: {not_ready}"
                ) from None
        await asyncio.sleep(POLL_INTERVAL_SECONDS)


class FailureKind(enum.Enum):
    COMMAND = enum.auto()
    COMPANION_UNREACHABLE = enum.auto()
    HOST_SERVICE_UNAVAILABLE = enum.auto()


def classify_failure(completed: Completed) -> FailureKind:
    for marker in COMPANION_UNREACHABLE_MARKERS:
        if marker in completed.error_text:
            return FailureKind.COMPANION_UNREACHABLE
    for marker in HOST_SERVICE_UNAVAILABLE_MARKERS:
        if marker in completed.error_text:
            return FailureKind.HOST_SERVICE_UNAVAILABLE
    return FailureKind.COMMAND


def strict() -> bool:
    return os.environ.get(STRICT_ENV) == "1"


def read_only_client() -> bool:
    return os.environ.get(READ_ONLY_CLIENT_ENV) == "1"


@dataclass(frozen=True)
class Completed:
    returncode: int
    stdout: bytes
    stderr: bytes

    @property
    def text(self) -> str:
        return self.stdout.decode(errors="replace")

    @property
    def error_text(self) -> str:
        return self.stderr.decode(errors="replace")


async def run(
    argv: Sequence[str],
    timeout: float,
    stdin: bytes | None = None,
    env: Mapping[str, str] | None = None,
) -> Completed:
    process = await asyncio.create_subprocess_exec(
        *argv,
        env=env,
        stdin=asyncio.subprocess.PIPE
        if stdin is not None
        else asyncio.subprocess.DEVNULL,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    try:
        stdout, stderr = await asyncio.wait_for(process.communicate(stdin), timeout)
    except asyncio.TimeoutError:
        process.kill()
        await process.wait()
        raise HarnessError(
            f"{' '.join(argv)} did not finish within {timeout:.0f}s"
        ) from None
    return Completed(process.returncode or 0, stdout, stderr)


class Simctl:
    """Read simulator state independently of idb."""

    def __init__(self, udid: str, device_set_path: Path) -> None:
        self.udid = udid
        self.device_set_path = device_set_path

    def argv(self, *args: str) -> list[str]:
        return ["xcrun", "simctl", "--set", str(self.device_set_path), *args]

    async def run(self, *args: str, timeout: float = 60.0) -> Completed:
        return await run(self.argv(*args), timeout=timeout)

    async def state(self) -> str | None:
        completed = await self.run("list", "-j", "devices")
        if completed.returncode != 0:
            return None
        return _device_states(json.loads(completed.stdout)).get(self.udid)

    async def installed_bundle_ids(self) -> set[str]:
        completed = await self.run("listapps", self.udid)
        if completed.returncode != 0:
            raise HarnessError(
                f"simctl listapps failed (rc={completed.returncode}): {completed.error_text}"
            )
        # listapps writes an old-style plist, which json cannot read.
        converted = await run(
            ["plutil", "-convert", "json", "-o", "-", "-"],
            timeout=60.0,
            stdin=completed.stdout,
        )
        if converted.returncode != 0:
            raise HarnessError(
                f"simctl listapps output could not be converted to JSON "
                f"(rc={converted.returncode}): {converted.error_text}"
            )
        return set(json.loads(converted.stdout).keys())

    async def running_bundle_ids(self) -> set[str]:
        completed = await self.run("spawn", self.udid, "launchctl", "list")
        if completed.returncode != 0:
            raise HarnessError(
                f"simctl could not list the simulator's services "
                f"(rc={completed.returncode}): {completed.error_text}"
            )
        return running_bundle_ids_from_listing(completed.text)

    async def app_container(self, bundle_id: str, kind: str = "data") -> Path:
        completed = await self.run("get_app_container", self.udid, bundle_id, kind)
        if completed.returncode != 0:
            raise HarnessError(
                f"simctl has no {kind} container for {bundle_id} "
                f"(rc={completed.returncode}): {completed.error_text}"
            )
        path = completed.text.strip()
        if not path:
            raise HarnessError(f"simctl reported no {kind} container for {bundle_id}")
        return Path(path)


# A stopped launchd job remains in the listing with `-` instead of a PID. Only
# positive-PID UIKitApplication rows prove that an application is still alive.
_APPLICATION_LINE = re.compile(
    r"(?m)^\s*([1-9][0-9]*)\s+\S+\s+UIKitApplication:([^\[\s]+)"
)


def running_bundle_ids_from_listing(listing: str) -> set[str]:
    """The bundle ids of apps with live processes in a launchctl listing."""
    return {bundle_id for _, bundle_id in _APPLICATION_LINE.findall(listing)}


def _device_states(listing: dict[str, Any]) -> dict[str, str]:
    states: dict[str, str] = {}
    for devices in listing.get("devices", {}).values():
        for device in devices:
            states[device["udid"]] = device.get("state", "")
    return states


class Environment:
    def __init__(
        self,
        udid: str,
        device_set_path: Path,
        idb_bin: Path,
        idb_args: Sequence[str],
        setup_idb_bin: Path,
        companion_path: Path,
        recorder_path: Path,
    ) -> None:
        self.udid = udid
        self.device_set_path = device_set_path
        self.idb_bin = idb_bin
        self.idb_args = tuple(idb_args)
        self.setup_idb_bin = setup_idb_bin
        self.companion_path = companion_path
        self.recorder_path = recorder_path
        self.simctl = Simctl(udid, device_set_path)

    @property
    def fixture_app(self) -> Path:
        return self.companion_path.parent / "Resources" / FIXTURE_APP_NAME

    @classmethod
    async def resolve(cls) -> "Environment":
        idb_bin = _binary_from_environment(IDB_BIN_ENV)
        idb_args = shlex.split(os.environ.get(IDB_ARGS_ENV, ""))
        setup_idb_bin = _optional_binary_from_environment(IDB_SETUP_BIN_ENV, idb_bin)
        companion_path = _binary_from_environment(IDB_E2E_COMPANION_PATH_ENV)
        recorder_path = _binary_from_environment(IDB_E2E_RECORDER_PATH_ENV)
        udid = _required(DEVICE_UDID_ENV, "the booted simulator to test against")
        device_set_path = Path(
            _required(DEVICE_SET_PATH_ENV, f"the device set {DEVICE_UDID_ENV} lives in")
        )
        if not device_set_path.is_dir():
            raise HarnessError(
                f"{DEVICE_SET_PATH_ENV}={device_set_path} is not a directory"
            )

        simctl = Simctl(udid, device_set_path)
        state = await simctl.state()
        if state is None:
            raise HarnessError(
                f"{DEVICE_UDID_ENV}={udid} is not present in {device_set_path}"
            )
        if state != "Booted":
            raise HarnessError(
                f"{DEVICE_UDID_ENV}={udid} must already be booted; it is {state}"
            )
        return cls(
            udid,
            device_set_path,
            idb_bin,
            idb_args,
            setup_idb_bin,
            companion_path,
            recorder_path,
        )


def _required(name: str, meaning: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise HarnessError(f"{name} is not set; it names {meaning}.")
    return value


def _optional_binary_from_environment(name: str, default: Path) -> Path:
    value = os.environ.get(name)
    return default if not value else _executable(Path(value), name)


def _binary_from_environment(name: str) -> Path:
    return _executable(Path(_required(name, "a binary this suite drives")), name)


def _executable(path: Path, name: str) -> Path:
    if not path.is_file() or not os.access(path, os.X_OK):
        raise HarnessError(f"{name}={path} is not an executable file")
    return path


def artifact_directory() -> Path | None:
    value = os.environ.get(ARTIFACTS_ENV) or os.environ.get("TEST_RESULT_ARTIFACTS_DIR")
    if not value:
        return None
    directory = Path(value)
    directory.mkdir(parents=True, exist_ok=True)
    return directory


class Companion:
    """Share a companion across tests.

    Use Popen because IsolatedAsyncioTestCase replaces the event loop after
    each test, while the companion must keep running.
    """

    def __init__(self, environment: Environment) -> None:
        # Use /tmp to stay within the Unix socket path limit on macOS.
        self.directory = Path(tempfile.mkdtemp(prefix="idb-e2e-", dir="/tmp"))
        self.socket_path = self.directory / "companion.sock"
        artifacts = artifact_directory()
        self.log_path = (
            artifacts / f"{self.directory.name}-companion.log"
            if artifacts is not None
            else self.directory / "companion.log"
        )
        self.process = subprocess.Popen(
            [
                str(environment.companion_path),
                "--udid",
                environment.udid,
                "--device-set-path",
                str(environment.device_set_path),
                "--grpc-domain-sock",
                str(self.socket_path),
                "--log-file-path",
                str(self.log_path),
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            stdin=subprocess.DEVNULL,
        )
        try:
            self.address = self._wait_until_ready()
        except BaseException:
            self.stop()
            raise

    def _wait_until_ready(self) -> str:
        # The companion reports readiness as a JSON line containing grpc_path.
        stdout = self.process.stdout
        assert stdout is not None
        deadline = Deadline(COMPANION_READY_TIMEOUT_SECONDS)
        while True:
            remaining = deadline.remaining
            if remaining <= 0:
                raise HarnessError(
                    f"The companion did not report ready within "
                    f"{deadline.seconds:.0f}s; log: {self.log_excerpt()}"
                )
            if self.process.poll() is not None:
                raise HarnessError(
                    f"The companion exited with {self.process.returncode} before "
                    f"reporting ready; log: {self.log_excerpt()}"
                )
            ready, _, _ = select.select(
                [stdout], [], [], min(remaining, POLL_INTERVAL_SECONDS)
            )
            if not ready:
                continue
            line = stdout.readline()
            if not line:
                continue
            try:
                report = json.loads(line)
            except ValueError:
                continue
            path = report.get("grpc_path") if isinstance(report, dict) else None
            if path:
                return str(path)

    def died(self) -> CompanionDied | None:
        """Return an error with the exit code and log if the companion exited."""
        returncode = self.process.poll()
        if returncode is None:
            return None
        return CompanionDied(
            f"The companion exited with {returncode}; stopping the test suite.\n"
            f"companion log: {self.log_excerpt()}"
        )

    def status_description(self) -> str:
        returncode = self.process.poll()
        if returncode is None:
            return "the companion is still running"
        return f"the companion exited with {returncode}"

    def log_excerpt(self, limit: int = 4000) -> str:
        try:
            return self.log_path.read_text(errors="replace")[-limit:]
        except OSError:
            return "<no companion log>"

    def stop(self) -> None:
        if self.process.poll() is None:
            self.process.send_signal(signal.SIGTERM)
            try:
                self.process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()
        if self.process.stdout is not None:
            self.process.stdout.close()


def client_argv(
    idb_bin: Path,
    idb_args: Sequence[str],
    companion_address: str,
    *args: str,
) -> list[str]:
    return [str(idb_bin), *idb_args, "--companion", companion_address, *args]


def idb_argv(environment: Environment, companion: Companion, *args: str) -> list[str]:
    return client_argv(
        environment.idb_bin,
        environment.idb_args,
        companion.address,
        *args,
    )


async def wait_for_accessibility(
    environment: Environment, companion: Companion
) -> None:
    """Wait for an accessibility read before running tests.

    A booted simulator may not have an accessibility translation object yet.
    """

    async def probe() -> None:
        completed = await run(
            idb_argv(environment, companion, *ACCESSIBILITY_PROBE_ARGS),
            timeout=DEFAULT_COMMAND_TIMEOUT_SECONDS,
        )
        if completed.returncode == 0:
            return
        kind = classify_failure(completed)
        if kind is FailureKind.HOST_SERVICE_UNAVAILABLE:
            # Let individual tests report the unavailable service as a skip or failure.
            return
        if kind is not FailureKind.COMMAND or (
            ACCESSIBILITY_NOT_READY_MARKER not in completed.error_text
        ):
            raise HarnessError(
                f"Accessibility setup failed: "
                f"idb {' '.join(ACCESSIBILITY_PROBE_ARGS)} "
                f"(rc={completed.returncode}): {completed.error_text}"
            )
        raise NotReady("no accessibility translation object")

    await wait_until(
        "The simulator did not begin serving accessibility reads",
        ACCESSIBILITY_READY_TIMEOUT_SECONDS,
        probe,
    )


_environment: Environment | None = None
_companion: Companion | None = None
_recording: Recording | None = None
_acquisition_failure: BaseException | None = None


async def shared_environment() -> Environment:
    """Validate the environment once and cache any setup failure."""
    global _environment, _acquisition_failure
    if _acquisition_failure is not None:
        raise _acquisition_failure
    if _environment is None:
        try:
            _environment = await Environment.resolve()
        except BaseException as error:
            _acquisition_failure = error
            raise
    return _environment


async def shared_companion() -> Companion:
    global _companion, _acquisition_failure
    if _acquisition_failure is not None:
        raise _acquisition_failure
    if _companion is None:
        environment = await shared_environment()
        try:
            companion = Companion(environment)
        except BaseException as error:
            _acquisition_failure = error
            raise
        try:
            await wait_for_accessibility(environment, companion)
        except BaseException as error:
            companion.stop()
            _acquisition_failure = error
            raise
        _companion = companion
        atexit.register(_companion.stop)
    return _companion


async def shared_recording(environment: Environment, companion: Companion) -> Recording:
    global _recording
    if _recording is None:
        _recording = Recording(
            environment.recorder_path,
            environment.udid,
            environment.device_set_path,
            artifact_directory() or companion.directory,
            companion.directory.name,
        )
        atexit.register(_recording.trace.close)
        atexit.register(_recording.stop)
        await _recording.wait_until_ready()
    return _recording


class IdbEndToEndTestCase(unittest.IsolatedAsyncioTestCase):
    """Run CLI tests against the shared companion and simulator."""

    environment: Environment
    companion: Companion
    recording: Recording | None = None

    # Keep the result so companion death can stop the remaining tests.
    _result: unittest.TestResult | None = None

    def run(self, result: unittest.TestResult | None = None) -> Any:
        self._result = result if result is not None else self.defaultTestResult()
        counts = self._result_counts()
        started = time.monotonic()
        try:
            return super().run(self._result)
        finally:
            if self.recording is not None:
                status = next(
                    (
                        name
                        for name, count in self._result_counts().items()
                        if count > counts[name]
                    ),
                    "passed",
                )
                self.recording.finish_test(status)
                self.recording.event(
                    "test_duration", seconds=time.monotonic() - started
                )

    def _result_counts(self) -> dict[str, int]:
        assert self._result is not None
        return {
            "error": len(self._result.errors),
            "failed": len(self._result.failures),
            "unexpected_success": len(self._result.unexpectedSuccesses),
            "skipped": len(self._result.skipped),
            "expected_failure": len(self._result.expectedFailures),
        }

    async def asyncSetUp(self) -> None:
        await super().asyncSetUp()
        self.environment = await shared_environment()
        self.companion = await shared_companion()
        self.recording = await shared_recording(self.environment, self.companion)
        self.recording.start_test(self.id())
        self.check_companion()

    async def asyncTearDown(self) -> None:
        if self.recording is not None:
            if await self.recording.screenshot() is None:
                try:
                    screenshot = await self.idb("screenshot", "-", check=False)
                except HarnessError as error:
                    self.recording.event("screenshot_unavailable", reason=str(error))
                else:
                    if screenshot.returncode == 0:
                        self.recording.save_screenshot(screenshot.stdout)
                    else:
                        self.recording.event(
                            "screenshot_unavailable", reason=screenshot.error_text
                        )
        await super().asyncTearDown()

    def check_companion(self) -> None:
        died = self.companion.died()
        if died is None:
            return
        self._stop_suite()
        raise died

    def _stop_suite(self) -> None:
        """Stop after this test reports its result.

        The remaining tests cannot run without the shared companion. Ordinary
        command failures leave the suite running.
        """
        if self._result is not None:
            self._result.stop()

    @property
    def udid(self) -> str:
        return self.environment.udid

    @property
    def simctl(self) -> Simctl:
        return self.environment.simctl

    async def run_client(
        self,
        argv: Sequence[str],
        timeout: float,
        stdin: bytes | None = None,
    ) -> Completed:
        return await run(argv, timeout=timeout, stdin=stdin)

    async def idb(
        self,
        *args: str,
        check: bool = True,
        timeout: float = DEFAULT_COMMAND_TIMEOUT_SECONDS,
        stdin: bytes | None = None,
    ) -> Completed:
        """Run idb; with check=True, report nonzero exits as failures or skips."""
        started = time.monotonic()
        if self.recording is not None:
            self.recording.command(["idb", *args])
        try:
            completed = await self.run_client(
                idb_argv(self.environment, self.companion, *args),
                timeout=timeout,
                stdin=stdin,
            )
        except BaseException as error:
            if self.recording is not None:
                self.recording.event(
                    "command_error",
                    argv=["idb", *args],
                    error=str(error),
                    seconds=time.monotonic() - started,
                )
            raise
        if self.recording is not None:
            self.recording.event(
                "command_finished",
                argv=["idb", *args],
                returncode=completed.returncode,
                seconds=time.monotonic() - started,
            )
        if check and completed.returncode != 0:
            self.fail_or_skip_for(" ".join(args), completed)
        return completed

    async def setup_idb(
        self,
        *args: str,
        check: bool = True,
        timeout: float = DEFAULT_COMMAND_TIMEOUT_SECONDS,
    ) -> Completed:
        """Run a fixture-preparation command outside the client under test."""
        completed = await run(
            client_argv(
                self.environment.setup_idb_bin,
                (),
                self.companion.address,
                *args,
            ),
            timeout=timeout,
        )
        if check and completed.returncode != 0:
            self.fail_or_skip_for("setup: " + " ".join(args), completed)
        return completed

    async def setup_terminate_quietly(self, bundle_id: str) -> None:
        await self.setup_idb("terminate", bundle_id, check=False)

    async def setup_uninstall_quietly(self, bundle_id: str) -> None:
        await self.setup_terminate_quietly(bundle_id)
        await self.setup_idb("uninstall", bundle_id, check=False)

    def idb_process(self, *args: str) -> "IdbProcess":
        """Start a streaming command and stop it when the async context exits."""
        return IdbProcess(
            self, idb_argv(self.environment, self.companion, *args), " ".join(args)
        )

    def fail_or_skip_for(self, what: str, completed: Completed) -> NoReturn:
        """Report command output; skip unsupported hosts unless strict mode is set.

        Include companion status for connection failures, and stop the suite if
        the companion has exited.
        """
        message = (
            f"idb {what} failed (rc={completed.returncode})\n"
            f"stdout: {completed.text}\n"
            f"stderr: {completed.error_text}"
        )
        kind = classify_failure(completed)

        if kind is FailureKind.COMPANION_UNREACHABLE:
            if self.companion.died() is not None:
                self._stop_suite()
            self.fail(
                f"The client could not reach the companion; "
                f"{self.companion.status_description()}.\n{message}\n"
                f"companion log: {self.companion.log_excerpt()}"
            )

        if kind is FailureKind.HOST_SERVICE_UNAVAILABLE:
            if strict():
                self.fail(
                    f"{STRICT_ENV}=1 and the simulator's host does not run "
                    f"SimLaunchHostService: {message}"
                )
            self.skipTest(
                f"This simulator's host does not run SimLaunchHostService; nothing "
                f"can be spawned in the guest: idb {what}"
            )

        # Preserve the command error even if the companion exited afterwards.
        companion_returncode = self.companion.process.poll()
        if companion_returncode is not None:
            self._stop_suite()
            self.fail(
                f"{message}\n"
                f"The companion has since exited with {companion_returncode}, so "
                f"later commands will fail to connect.\n"
                f"companion log: {self.companion.log_excerpt()}"
            )
        self.fail(message)

    async def idb_text(self, *args: str, **kwargs: Any) -> str:
        return (await self.idb(*args, **kwargs)).text

    async def idb_json(self, *args: str, **kwargs: Any) -> Any:
        return json.loads(await self.idb_text(*args, "--json", **kwargs))

    async def idb_json_lines(self, *args: str, **kwargs: Any) -> list[Any]:
        text = await self.idb_text(*args, "--json", **kwargs)
        return [json.loads(line) for line in text.splitlines() if line.strip()]

    async def idb_expect_failure(self, *args: str, **kwargs: Any) -> Completed:
        """Require a command failure, rejecting connection and host-service errors."""
        kwargs["check"] = False
        completed = await self.idb(*args, **kwargs)
        if completed.returncode == 0:
            self.fail(
                f"idb {' '.join(args)} unexpectedly succeeded\nstdout: {completed.text}"
            )
        if classify_failure(completed) is not FailureKind.COMMAND:
            self.fail_or_skip_for(" ".join(args), completed)
        return completed

    async def installed_apps(self) -> dict[str, dict[str, Any]]:
        return {row["bundle_id"]: row for row in await self.idb_json_lines("list-apps")}

    async def setup_install_fixture_app(self) -> str:
        """Install the companion fixture with the setup client and queue removal."""
        fixture = self.environment.fixture_app
        if not fixture.is_dir():
            raise HarnessError(
                f"The companion's {FIXTURE_APP_NAME} is missing at {fixture}"
            )
        self.addAsyncCleanup(self.setup_uninstall_quietly, FIXTURE_APP_BUNDLE_ID)
        await self.setup_idb(
            "install",
            str(fixture),
            timeout=INSTALL_TIMEOUT_SECONDS,
        )
        return FIXTURE_APP_BUNDLE_ID

    async def install_fixture_app(self) -> str:
        """Install ReplHost.app, register uninstall cleanup, and return its bundle ID."""
        fixture = self.environment.fixture_app
        if not fixture.is_dir():
            raise HarnessError(
                f"The companion's {FIXTURE_APP_NAME} is missing at {fixture}"
            )
        self.addAsyncCleanup(self.uninstall_quietly, FIXTURE_APP_BUNDLE_ID)
        await self.idb("install", str(fixture), timeout=INSTALL_TIMEOUT_SECONDS)
        return FIXTURE_APP_BUNDLE_ID

    async def uninstall_quietly(self, bundle_id: str) -> None:
        await self.idb("terminate", bundle_id, check=False)
        await self.idb("uninstall", bundle_id, check=False)

    async def terminate_quietly(self, bundle_id: str) -> None:
        await self.idb("terminate", bundle_id, check=False)

    def make_temporary_directory(self) -> Path:
        directory = Path(tempfile.mkdtemp(prefix="idb-e2e-test-"))
        self.addCleanup(shutil.rmtree, directory, True)
        return directory


class IdbProcess:
    """Manage a streaming idb subprocess with an async context manager."""

    def __init__(
        self, test: IdbEndToEndTestCase, argv: Sequence[str], what: str
    ) -> None:
        self._test = test
        self._argv = list(argv)
        self._what = what
        self._process: asyncio.subprocess.Process | None = None
        self._stderr: bytes = b""

    async def __aenter__(self) -> "IdbProcess":
        if self._test.recording is not None:
            self._test.recording.command(["idb", *self._argv[3:]])
        self._process = await asyncio.create_subprocess_exec(
            *self._argv,
            stdin=asyncio.subprocess.DEVNULL,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        return self

    async def __aexit__(self, *exception: object) -> None:
        process = self._process
        if process is None:
            return
        if process.returncode is None:
            process.terminate()
        try:
            _, self._stderr = await asyncio.wait_for(process.communicate(), 60.0)
        except asyncio.TimeoutError:
            process.kill()
            await process.wait()

        if self._test.recording is not None:
            self._test.recording.event(
                "command_finished",
                argv=["idb", *self._argv[3:]],
                returncode=process.returncode,
            )

    @property
    def stdout(self) -> asyncio.StreamReader:
        process = self._process
        assert process is not None and process.stdout is not None
        return process.stdout

    @property
    def returncode(self) -> int | None:
        process = self._process
        return None if process is None else process.returncode

    async def read_some(self, timeout: float) -> bytes:
        """Read a stdout chunk. Some commands omit newlines, so readline can block."""
        try:
            data = await asyncio.wait_for(self.stdout.read(4096), timeout)
        except asyncio.TimeoutError:
            self._test.fail(
                f"idb {self._what} wrote nothing to stdout within {timeout:.0f}s"
            )
        if not data:
            self._test.fail(f"idb {self._what} closed stdout without writing anything")
        return data

    async def wait_for_exit(self, timeout: float) -> int:
        process = self._process
        assert process is not None
        try:
            return await asyncio.wait_for(process.wait(), timeout)
        except asyncio.TimeoutError:
            self._test.fail(f"idb {self._what} did not exit within {timeout:.0f}s")

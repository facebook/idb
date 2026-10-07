/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBXCTestCore
import XCTest

/// Covers `LogicTestRunStrategy` end to end on the host. The script plays the shim by writing
/// newline-delimited events to `TEST_SHIM_STDOUT_PATH`.
final class LogicTestRunStrategyTests: XCTestCase {

  private static let shimPath = "/nonexistent/libShimulator.dylib"

  private struct Launch {
    let executable: String
    let arguments: [String]
    let environment: [String: String]
    let posixSpawn: Bool
  }

  private func launches(of target: ScriptedLogicTestTarget) -> [Launch] {
    target.spawned.compactMap { subprocess -> Launch? in
      guard case .exact(let environment) = subprocess.environment else {
        XCTFail("Expected exactly the prepared environment, got \(subprocess.environment)")
        return nil
      }
      return Launch(executable: subprocess.executable, arguments: subprocess.arguments, environment: environment, posixSpawn: subprocess.mode == .posixSpawn)
    }
  }

  private func runTests(
    running script: String,
    environment: [String: String] = [:],
    testFilter: String? = nil,
    timeout: TimeInterval = 30,
    coverageDirectory: String? = nil,
    logDirectoryPath: String? = nil,
    injectLibraries: [String] = []
  ) async throws -> (target: ScriptedLogicTestTarget, reporter: RecordingLogicReporter, result: Result<Void, any Error>) {
    let target = ScriptedLogicTestTarget(shimPath: Self.shimPath, script: script)
    let reporter = RecordingLogicReporter()
    let configuration = LogicTestConfiguration(
      environment: environment,
      workingDirectory: NSTemporaryDirectory(),
      testBundlePath: Self.macUnitTestBundleFixture().bundlePath,
      waitForDebugger: false,
      timeout: timeout,
      testFilter: testFilter,
      mirroring: [],
      coverageConfiguration: coverageDirectory.map { CodeCoverageConfiguration(directory: $0, format: .exported, enableContinuousCoverageCollection: false) },
      binaryPath: nil,
      logDirectoryPath: logDirectoryPath,
      architectures: ["arm64", "x86_64"],
      injectLibraries: injectLibraries
    )
    let strategy = LogicTestRunStrategy(target: target, configuration: configuration, reporter: reporter, logger: ControlCoreGlobalConfiguration.defaultLogger)
    do {
      try await strategy.run()
      return (target, reporter, .success(()))
    } catch {
      return (target, reporter, .failure(error))
    }
  }

  func testShimEventsReachTheReporterBetweenTheStartAndFinishOfThePlan() async throws {
    let (_, reporter, result) = try await runTests(
      running: """
        printf '{"event":"begin-test"}\\n{"event":"end-test"}\\n' > "$TEST_SHIM_STDOUT_PATH"
        """)

    try result.get()
    XCTAssertEqual(reporter.calls, ["didBegin", "event {\"event\":\"begin-test\"}", "event {\"event\":\"end-test\"}", "didFinish"])
  }

  func testLaunchesAThinnedXCTestWithTheShimInjected() async throws {
    let (target, _, result) = try await runTests(
      running: "exit 0",
      environment: ["PROCESS_UNDER_TEST": "1"],
      testFilter: "FooTests/testBar",
      coverageDirectory: "/tmp/coverage",
      logDirectoryPath: "/tmp/logs",
      injectLibraries: ["/tmp/libInjected.dylib"])

    try result.get()
    let launches = launches(of: target)
    XCTAssertEqual(launches.count, 1)
    let launch = try XCTUnwrap(launches.first)
    let architecture = ArchitectureProcessAdapter.hostMachineSupportedArchitectures().contains(.arm64) ? "arm64" : "x86_64"
    XCTAssertNotEqual(launch.executable, target.xctest.path, "The universal xctest binary is thinned to a copy before launch")
    XCTAssertTrue((launch.executable as NSString).lastPathComponent.hasPrefix("xctest"), launch.executable)
    XCTAssertTrue(launch.executable.hasSuffix(".\(architecture)"), launch.executable)
    XCTAssertEqual(launch.arguments, ["-XCTest", "FooTests/testBar", Self.macUnitTestBundleFixture().bundlePath])
    XCTAssertTrue(launch.posixSpawn)
    XCTAssertEqual(launch.environment["DYLD_INSERT_LIBRARIES"], "\(Self.shimPath):/tmp/libInjected.dylib")
    XCTAssertEqual(launch.environment["TEST_SHIM_BUNDLE_PATH"], Self.macUnitTestBundleFixture().bundlePath)
    XCTAssertNotNil(launch.environment["TEST_SHIM_STDOUT_PATH"])
    XCTAssertEqual(launch.environment["XCTOOL_WAIT_FOR_DEBUGGER"], "NO")
    XCTAssertEqual(launch.environment["LLVM_PROFILE_FILE"], "/tmp/coverage/coverage_\((Self.macUnitTestBundleFixture().bundlePath as NSString).lastPathComponent).profraw")
    XCTAssertEqual(launch.environment["LOG_DIRECTORY_PATH"], "/tmp/logs")
    XCTAssertEqual(launch.environment["PROCESS_UNDER_TEST"], "1", "The process-under-test environment is passed through")
    XCTAssertEqual(launch.environment["IDB_TARGET_ADDITION"], "1", "The target's environment additions are applied")
    XCTAssertNotNil(launch.environment["DYLD_FRAMEWORK_PATH"])
    XCTAssertNotNil(launch.environment["DYLD_LIBRARY_PATH"])
  }

  func testWithoutAFilterAllTestsAreRun() async throws {
    let (target, _, result) = try await runTests(running: "exit 0")

    try result.get()
    XCTAssertEqual(launches(of: target).first?.arguments, ["-XCTest", "All", Self.macUnitTestBundleFixture().bundlePath])
  }

  func testAFailureExitCodeFailsWithTheStandardErrorMostRecentFirst() async throws {
    let (_, reporter, result) = try await runTests(running: "echo first >&2; echo second >&2; exit 11")

    guard case .failure(LogicTestRunError.xctestProcessFailed(let exitCode, let exitDescription, let stdErr)) = result else {
      return XCTFail("Expected the run to fail, got \(result)")
    }
    XCTAssertEqual(exitCode, 11)
    XCTAssertEqual(exitDescription, "Error opening test bundle")
    XCTAssertEqual(stdErr, "\nsecond\nfirst")
    XCTAssertEqual(reporter.calls.first, "didBegin")
    XCTAssertEqual(reporter.calls.last, "didCrash")
  }

  func testExitCodeOneIsNotAFailure() async throws {
    let (_, reporter, result) = try await runTests(running: "exit 1")

    try result.get()
    XCTAssertEqual(reporter.calls, ["didBegin", "didFinish"])
  }

  func testAStalledProcessIsTerminatedAfterTheTimeout() async throws {
    let started = ContinuousClock.now
    let (_, reporter, result) = try await runTests(running: "exec sleep 30", timeout: 1)

    guard case .failure(XCTestProcessError.stalled(let timeout, let processIdentifier, _)) = result else {
      return XCTFail("Expected the run to stall, got \(result)")
    }
    defer { kill(processIdentifier, SIGKILL) }
    XCTAssertEqual(timeout, 1)
    try await Task.sleep(nanoseconds: 3_000_000_000)
    XCTAssertNotEqual(kill(processIdentifier, 0), 0, "The stalled process is terminated")
    XCTAssertEqual(reporter.calls.last, "didCrash")
    XCTAssertLessThan(ContinuousClock.now - started, .seconds(20))
  }
}

// MARK: - Reporter double

// SAFETY: `recorded` is only read or written inside `lock`.
// patternlint-disable-next-line unchecked-sendable
private final class RecordingLogicReporter: LogicXCTestReporter, @unchecked Sendable {

  private let lock = NSLock()
  private var recorded: [String] = []

  var calls: [String] {
    lock.withLock { recorded }
  }

  private func record(_ call: String) {
    lock.withLock { recorded.append(call) }
  }

  func processWaitingForDebugger(withProcessIdentifier pid: pid_t) {
    record("waitingForDebugger")
  }

  func didBeginExecutingTestPlan() {
    record("didBegin")
  }

  func didFinishExecutingTestPlan() {
    record("didFinish")
  }

  // Standard output arrives asynchronously relative to the plan's completion, so it is not recorded.
  func testHadOutput(_ output: String) {}

  func handleEventJSONData(_ data: Data) {
    record("event \(String(data: data, encoding: .utf8) ?? "")")
  }

  func didCrashDuringTest(_ error: Error) {
    record("didCrash")
  }
}

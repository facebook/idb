/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import XCTest
@testable import XCTestBootstrap

/// Covers `ListTestStrategy` end to end on the host. The real shim cannot be loaded here, so the
/// target spawns a shell script in place of the `xctest` binary, handing it the environment and
/// output streams the strategy prepared; the script plays the shim by writing the test list to
/// `TEST_SHIM_OUTPUT_PATH`.
final class ListTestStrategyTests: XCTestCase {

  private static let shimPath = "/nonexistent/libShimulator.dylib"

  private func listTests(running script: String, timeout: TimeInterval = 30) async throws -> (tests: [String], target: ScriptedLogicTestTarget) {
    let target = ScriptedLogicTestTarget(shimPath: Self.shimPath, script: script)
    let configuration = ListTestConfiguration(
      environment: [:],
      workingDirectory: NSTemporaryDirectory(),
      testBundlePath: Self.macUnitTestBundleFixture().bundlePath,
      runnerAppPath: nil,
      waitForDebugger: false,
      timeout: timeout,
      architectures: ["arm64", "x86_64"]
    )
    let tests: [String] = try await bridgeFBFutureArray(ListTestStrategy(target: target, configuration: configuration, logger: ControlCoreGlobalConfiguration.defaultLogger).listTests())
    return (tests, target)
  }

  func testReturnsTheTestNamesTheShimWrites() async throws {
    let (tests, _) = try await listTests(
      running: """
        printf '[{"legacyTestName":"FooTests/testBar"},{"legacyTestName":"FooTests/testBaz"}]' > "$TEST_SHIM_OUTPUT_PATH"
        """)

    XCTAssertEqual(tests, ["FooTests/testBar", "FooTests/testBaz"])
  }

  func testSpawnsAThinnedXCTestWithTheShimInjected() async throws {
    let (_, target) = try await listTests(running: "printf '[]' > \"$TEST_SHIM_OUTPUT_PATH\"")

    let spawned = try XCTUnwrap(target.spawned.first)
    XCTAssertEqual(target.spawned.count, 1)
    let xctestPath = target.xctest.path
    let architecture = ArchitectureProcessAdapter.hostMachineSupportedArchitectures().contains(.arm64) ? "arm64" : "x86_64"
    XCTAssertNotEqual(spawned.launchPath, xctestPath, "The universal xctest binary is thinned to a copy before launch")
    XCTAssertTrue((spawned.launchPath as NSString).lastPathComponent.hasPrefix("xctest"), spawned.launchPath)
    XCTAssertTrue(spawned.launchPath.hasSuffix(".\(architecture)"), spawned.launchPath)
    XCTAssertEqual(spawned.arguments, [])
    XCTAssertEqual(spawned.mode, .default)
    XCTAssertEqual(spawned.environment["DYLD_INSERT_LIBRARIES"], Self.shimPath)
    XCTAssertEqual(spawned.environment["TEST_SHIM_BUNDLE_PATH"], Self.macUnitTestBundleFixture().bundlePath)
    XCTAssertNotNil(spawned.environment["TEST_SHIM_OUTPUT_PATH"])
    XCTAssertEqual(spawned.environment["IDB_TARGET_ADDITION"], "1", "The target's environment additions are applied")
    XCTAssertNotNil(spawned.environment["DYLD_FRAMEWORK_PATH"])
    XCTAssertNotNil(spawned.environment["DYLD_LIBRARY_PATH"])
  }

  func testAShimFailureExitCodeFailsWithTheStandardErrorMostRecentFirst() async throws {
    do {
      _ = try await listTests(running: "echo first >&2; echo second >&2; exit 11")
      XCTFail("Expected listing to fail")
    } catch let ListTestError.listingFailed(exitCode, exitDescription, stdErr) {
      XCTAssertEqual(exitCode, 11)
      XCTAssertEqual(exitDescription, "Error opening test bundle")
      XCTAssertEqual(stdErr, "\nsecond\nfirst")
    }
  }

  func testExitCodeOneIsNotAFailure() async throws {
    let (tests, _) = try await listTests(running: "printf '[{\"legacyTestName\":\"A/b\"}]' > \"$TEST_SHIM_OUTPUT_PATH\"; exit 1")

    XCTAssertEqual(tests, ["A/b"])
  }

  func testMalformedShimOutputFails() async throws {
    do {
      _ = try await listTests(running: "printf '{}' > \"$TEST_SHIM_OUTPUT_PATH\"")
      XCTFail("Expected listing to fail")
    } catch ListTestError.testListJSONParseFailed {
      // Expected.
    }
  }

  func testAnEntryWithoutATestNameFails() async throws {
    do {
      _ = try await listTests(running: "printf '[{\"name\":\"A/b\"}]' > \"$TEST_SHIM_OUTPUT_PATH\"")
      XCTFail("Expected listing to fail")
    } catch ListTestError.unexpectedTestName {
      // Expected.
    }
  }

  func testAProcessThatNeverWritesTheListFailsToParseTheEmptyOutput() async throws {
    do {
      _ = try await listTests(running: "exit 0")
      XCTFail("Expected listing to fail")
    } catch let error as NSError {
      XCTAssertEqual(error.domain, NSCocoaErrorDomain)
      XCTAssertEqual(error.code, NSPropertyListReadCorruptError)
    }
  }

  func testAStalledProcessIsTerminatedAfterTheTimeout() async throws {
    let started = ContinuousClock.now
    do {
      _ = try await listTests(running: "exec sleep 30", timeout: 1)
      XCTFail("Expected listing to fail")
    } catch let XCTestProcessError.stalled(timeout, processIdentifier, _) {
      defer { kill(processIdentifier, SIGKILL) }
      XCTAssertEqual(timeout, 1)
      try await Task.sleep(nanoseconds: 3_000_000_000)
      // BUG: the timeout races the process's own exit future, and losing the race cancels it, so
      // the termination that follows believes the process has already exited and never signals it.
      // Flipped in the following commit.
      XCTAssertEqual(kill(processIdentifier, 0), 0, "The stalled process is left running")
    }
    XCTAssertLessThan(ContinuousClock.now - started, .seconds(15))
  }

  func testAProcessKilledBySignalFails() async throws {
    do {
      _ = try await listTests(running: "kill -KILL $$")
      XCTFail("Expected listing to fail")
    } catch let ProcessTerminationError.exitedWithSignal(_, processName, signal) {
      XCTAssertEqual(processName, "sh")
      XCTAssertEqual(signal, SIGKILL)
    }
  }
}

// MARK: - Target double

/// A logic test target that forwards everything to the local Mac, except that the shim is a fixed
/// path and a spawn runs `script` under `/bin/sh` in place of the requested binary.
private final class ScriptedLogicTestTarget: NSObject, LogicTestTarget {

  private let device = MacDevice()
  private let script: String
  private let lock = NSLock()
  private var spawnedConfigurations: [ProcessSpawnConfiguration] = []
  let xctest: ShimmedXCTest

  init(shimPath: String, script: String) {
    self.script = script
    self.xctest = ShimmedXCTest(shimPath: shimPath, path: device.xctest.path)
  }

  var spawned: [ProcessSpawnConfiguration] {
    lock.withLock { spawnedConfigurations }
  }

  func spawn(_ configuration: ProcessSpawnConfiguration) async throws -> FBSubprocess<AnyObject, AnyObject, AnyObject> {
    lock.withLock { spawnedConfigurations.append(configuration) }
    let scripted = ProcessSpawnConfiguration(launchPath: "/bin/sh", arguments: ["-c", script], environment: Self.scriptEnvironment(configuration.environment), io: configuration.io, mode: configuration.mode)
    return try await bridgeFBFuture(FBSubprocess<AnyObject, AnyObject, AnyObject>.launchProcess(with: scripted, logger: logger))
  }

  /// SIP strips `DYLD_*` from `/bin/sh`, but not on every host: where it survives, dyld aborts the
  /// shell trying to insert the nonexistent shim before the script runs.
  private static func scriptEnvironment(_ environment: [String: String]) -> [String: String] {
    environment.filter { !$0.key.hasPrefix("DYLD_") }
  }

  func environmentAdditions() -> [String: String] {
    ["IDB_TARGET_ADDITION": "1"]
  }

  static func commands(with target: any Target) -> Self {
    fatalError("Not used by ListTestStrategy")
  }

  var uniqueIdentifier: String { device.uniqueIdentifier }
  var udid: String { device.udid }
  var name: String { device.name }
  var deviceType: DeviceType { device.deviceType }
  var architectures: [Architecture] { device.architectures }
  var osVersion: OSVersion { device.osVersion }
  var extendedInformation: [String: Any] { device.extendedInformation }
  var targetType: TargetType { device.targetType }
  var state: TargetState { device.state }
  func compare(_ target: any TargetInfo) -> ComparisonResult { device.compare(target) }

  var application: MacDevice { device }
  var crashLog: MacDevice { device }
  var debugServer: MacDevice { device }
  var file: MacDevice { device }
  var instruments: MacDevice { device }
  var lifecycle: MacDevice { device }
  var location: MacDevice { device }
  var log: MacDevice { device }
  var power: MacDevice { device }
  var screenshot: MacDevice { device }
  var videoRecording: MacDevice { device }
  var videoStream: MacDevice { device }
  var xctraceRecord: MacDevice { device }

  func erase() async throws { try await device.erase() }
  var logger: any ControlCoreLogger { device.logger }
  var customDeviceSetPath: String? { device.customDeviceSetPath }
  var temporaryDirectory: TemporaryDirectory { device.temporaryDirectory }
  var auxillaryDirectory: String { device.auxillaryDirectory }
  var runtimeRootDirectory: String { get async { await device.runtimeRootDirectory } }
  var platformRootDirectory: String { get async { await device.platformRootDirectory } }
  var screenInfo: TargetScreenInfo? { device.screenInfo }
  var workQueue: DispatchQueue { device.asyncQueue }
  var asyncQueue: DispatchQueue { device.asyncQueue }
  func requiresBundlesToBeSigned() -> Bool { device.requiresBundlesToBeSigned() }
  func replacementMapping() -> [String: String] { device.replacementMapping() }
}

private struct ShimmedXCTest: XCTestExtendedCommands {

  let shimPath: String
  let path: String

  func extendedTestShim() async throws -> String {
    shimPath
  }

  func runTest(launchConfiguration: TestLaunchConfiguration, reporter: AnyObject, logger: any ControlCoreLogger) async throws {
    fatalError("Not used by ListTestStrategy")
  }

  func listTests(forBundleAtPath bundlePath: String, timeout: TimeInterval, withAppAtPath appPath: String?) async throws -> [String] {
    fatalError("Not used by ListTestStrategy")
  }

  func withTransportForTestManagerService<R>(body: (NSNumber) async throws -> R) async throws -> R {
    fatalError("Not used by ListTestStrategy")
  }
}

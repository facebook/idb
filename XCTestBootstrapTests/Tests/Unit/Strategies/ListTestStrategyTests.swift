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
/// target's launcher runs a shell script in place of the `xctest` binary, handing it the environment
/// and output streams the strategy prepared; the script plays the shim by writing the test list to
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
    XCTAssertNotEqual(spawned.executable, xctestPath, "The universal xctest binary is thinned to a copy before launch")
    XCTAssertTrue((spawned.executable as NSString).lastPathComponent.hasPrefix("xctest"), spawned.executable)
    XCTAssertTrue(spawned.executable.hasSuffix(".\(architecture)"), spawned.executable)
    XCTAssertEqual(spawned.arguments, [])
    XCTAssertEqual(spawned.mode, .default)
    guard case .exact(let environment) = spawned.environment else {
      return XCTFail("Expected exactly the prepared environment, got \(spawned.environment)")
    }
    XCTAssertEqual(environment["DYLD_INSERT_LIBRARIES"], Self.shimPath)
    XCTAssertEqual(environment["TEST_SHIM_BUNDLE_PATH"], Self.macUnitTestBundleFixture().bundlePath)
    XCTAssertNotNil(environment["TEST_SHIM_OUTPUT_PATH"])
    XCTAssertEqual(environment["IDB_TARGET_ADDITION"], "1", "The target's environment additions are applied")
    XCTAssertNotNil(environment["DYLD_FRAMEWORK_PATH"])
    XCTAssertNotNil(environment["DYLD_LIBRARY_PATH"])
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
      XCTAssertNotEqual(kill(processIdentifier, 0), 0, "The stalled process is terminated")
    }
    XCTAssertLessThan(ContinuousClock.now - started, .seconds(15))
  }

  func testAProcessKilledBySignalFails() async throws {
    do {
      _ = try await listTests(running: "kill -KILL $$")
      XCTFail("Expected listing to fail")
    } catch let ProcessTerminationError.exitedWithSignal(_, processName, signal) {
      XCTAssertTrue(processName.hasPrefix("xctest"), processName)
      XCTAssertEqual(signal, SIGKILL)
    }
  }
}

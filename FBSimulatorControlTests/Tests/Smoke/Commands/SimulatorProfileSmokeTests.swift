/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import XCTest

/// Profiles a system application, so nothing has to be installed. A system application isn't debuggable, which is
/// what lets this cover a tool failing as well as succeeding.
final class SimulatorProfileSmokeTests: ProvidedSimulatorTestCase {

  private static let bundleID = "com.apple.mobilesafari"

  override func setUp() async throws {
    try await super.setUp()
    let simulator = self.simulator!
    let configuration = ApplicationLaunchConfiguration(
      bundleID: Self.bundleID,
      bundleName: nil,
      arguments: [],
      environment: [:],
      waitForDebugger: false,
      io: .outputToDevNull(),
      launchMode: .relaunchIfRunning)
    _ = try await simulator.application.launch(configuration)
    addTeardownBlock {
      try await simulator.application.kill(bundleID: Self.bundleID)
    }
  }

  func testFootprintReportsTheTarget() async throws {
    let pid = try await simulator.application.processID(forBundleID: Self.bundleID)

    let result = try await skippingIfGuestServiceSpawnUnavailable {
      try await simulator.profile.profile(.footprint, target: .bundleID(Self.bundleID)).result
    }

    guard case let .footprint(report) = result.report else {
      return XCTFail("Expected a footprint report, got \(String(describing: result.report))")
    }
    XCTAssertEqual(report.pid, pid)
    XCTAssertGreaterThan(report.footprintBytes, 0)
  }

  func testRuntimeToolFailureCarriesItsStderr() async throws {
    let operation = try await simulator.profile.profile(.leaks, target: .bundleID(Self.bundleID))

    do {
      let result = try await skippingIfGuestServiceSpawnUnavailable { try await operation.result }
      XCTFail("leaks can't examine a system application, but reported \(String(describing: result.report))")
    } catch let ProfileError.toolFailed(tool, exitCode, stderr) {
      XCTAssertEqual(tool, "leaks")
      XCTAssertNotEqual(exitCode, 0)
      XCTAssertTrue(stderr.contains("cannot examine"), stderr)
    }
  }

  func testToolKilledBySignalCarriesItsStderr() async throws {
    do {
      let output = try await skippingIfGuestServiceSpawnUnavailable {
        try await simulator.runtimeTools.launchConsumingOutput(launchPath: "/bin/sh", arguments: ["-c", "echo aborting >&2; kill -ABRT $$"])
      }
      XCTFail("sh killed itself with SIGABRT, but exited with code \(output.exitCode)")
    } catch let InSimulatorToolError.signalled(launchPath, signal, stderr) {
      XCTAssertEqual(launchPath, "/bin/sh")
      XCTAssertEqual(signal, SIGABRT)
      XCTAssertTrue(stderr.contains("aborting"), stderr)
    }
  }

  func testResourcesStreamUntilStopped() async throws {
    let pid = try await simulator.application.processID(forBundleID: Self.bundleID)
    let operation = try await simulator.profile.profile(.resources(interval: .milliseconds(100), scope: .app), target: .pid(pid))

    var samples: [ResourceSample] = []
    for await sample in operation.samples {
      samples.append(sample)
      if samples.count == 3 {
        operation.stop()
      }
    }
    let result = try await operation.result

    XCTAssertGreaterThanOrEqual(samples.count, 3)
    XCTAssertTrue(samples.allSatisfy { $0.pid == pid })
    XCTAssertNil(result.report)
  }

  func testCancellingTheConsumerEndsResources() async throws {
    let pid = try await simulator.application.processID(forBundleID: Self.bundleID)
    let operation = try await simulator.profile.profile(.resources(interval: .milliseconds(100), scope: .app), target: .pid(pid))
    let consumer = Task {
      for await _ in operation.samples {}
    }

    try await Task.sleep(for: .milliseconds(300))
    consumer.cancel()
    await consumer.value
    let result = try await operation.result

    XCTAssertNil(result.report)
  }

  func testTraceExportsTheTimeProfile() async throws {
    let configuration = TraceConfiguration(template: "Time Profiler", schemas: nil, timeLimit: .seconds(3), rowLimit: 10, outputPath: nil)

    let result = try await simulator.profile.profile(.trace(configuration), target: .bundleID(Self.bundleID)).result

    guard case let .trace(report) = result.report else {
      return XCTFail("Expected a trace report, got \(String(describing: result.report))")
    }
    XCTAssertEqual(report.runs.count, 1)
    XCTAssertEqual(report.runs.first?.templateName, "Time Profiler")
    XCTAssertEqual(report.tables.map(\.schema), ["time-profile"])
    XCTAssertLessThanOrEqual(report.tables.first?.rows.count ?? .max, 10)
    XCTAssertNil(result.artifact)
  }
}

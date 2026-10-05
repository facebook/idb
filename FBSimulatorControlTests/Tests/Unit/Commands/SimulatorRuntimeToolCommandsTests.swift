/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import XCTest

/// What `launchConsumingOutput` hands back from a process spawned inside the simulator,
/// driven against a device double that writes both streams and exits at once.
final class SimulatorRuntimeToolCommandsTests: XCTestCase {

  func testCapturesBothStreamsAndReturnsANonZeroExitCode() async throws {
    let device = ToolSpawnDevice(stdOut: Data("out\n".utf8), stdErr: Data("err\n".utf8), statLoc: 3 << 8)
    let commands = SimulatorRuntimeToolCommands(simulator: SimulatorTestSupport.testableSimulator(withDevice: device))

    let output = try await commands.launchConsumingOutput(launchPath: "/bin/sh", arguments: ["-c", "true"], environment: ["E": "1"])

    XCTAssertEqual(output.stdout, Data("out\n".utf8))
    XCTAssertEqual(output.stderr, Data("err\n".utf8))
    XCTAssertEqual(output.exitCode, 3, "Exit codes are not interpreted, so a non-zero exit is returned rather than thrown")
    let options = try XCTUnwrap(device.spawnedOptions)
    XCTAssertEqual(options["arguments"] as? [String], ["/bin/sh", "-c", "true"])
    XCTAssertEqual(options["environment"] as? [String: String], ["E": "1"])
  }

  func testGivesTheProcessOnlyTheEnvironmentItIsHanded() async throws {
    let device = ToolSpawnDevice()
    let commands = SimulatorRuntimeToolCommands(simulator: SimulatorTestSupport.testableSimulator(withDevice: device))

    _ = try await commands.launchConsumingOutput(launchPath: "/bin/sh")

    XCTAssertEqual(device.spawnedOptions?["environment"] as? [String: String], [:])
  }

  func testThrowsWhenTheProcessIsSignalled() async throws {
    let device = ToolSpawnDevice(statLoc: SIGKILL)
    let commands = SimulatorRuntimeToolCommands(simulator: SimulatorTestSupport.testableSimulator(withDevice: device))

    do {
      let output = try await commands.launchConsumingOutput(launchPath: "/bin/sh")
      XCTFail("Expected a signalled process to throw, but it returned exit code \(output.exitCode)")
    } catch {
      // Expected: there is no exit code to report.
    }
  }
}

// MARK: - Device double

/// Writes the given payloads into the stdout and stderr descriptors it is handed, then
/// reports termination before anything has read them.
private final class ToolSpawnDevice: @unchecked Sendable {
  @objc(UDID) let udid = NSUUID()
  @objc let state = UInt64(TargetState.booted.rawValue)

  private let stdOut: Data
  private let stdErr: Data
  private let statLoc: Int32
  private(set) var spawnedOptions: [String: Any]?

  init(stdOut: Data = Data(), stdErr: Data = Data(), statLoc: Int32 = 0) {
    self.stdOut = stdOut
    self.stdErr = stdErr
    self.statLoc = statLoc
  }

  @objc(spawnAsyncWithPath:options:terminationQueue:terminationHandler:completionQueue:completionHandler:)
  func spawnAsync(
    withPath path: String,
    options: [String: Any],
    terminationQueue: DispatchQueue,
    terminationHandler: @escaping (Int32) -> Void,
    completionQueue: DispatchQueue,
    completionHandler: @escaping (NSError?, pid_t) -> Void
  ) {
    spawnedOptions = options
    for (key, payload) in [("stdout", stdOut), ("stderr", stdErr)] {
      if let fileDescriptor = (options[key] as? NSNumber)?.int32Value {
        payload.withUnsafeBytes { _ = write(fileDescriptor, $0.baseAddress, $0.count) }
      }
    }
    let statLoc = statLoc
    completionQueue.async {
      completionHandler(nil, 4242)
      terminationQueue.async { terminationHandler(statLoc) }
    }
  }
}

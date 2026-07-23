/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import XCTest

/// Characterizes how `FBSimulator`'s spawn paths build the `SimDevice` launch-option
/// dictionary. These are pure-function assertions over the option builders, so they
/// hold without a booted simulator and lock the behavior that the spawn-path
/// consolidation must preserve (argv[0] handling, `standalone` resolution, stdio keys).
final class FBSimulatorProcessSpawnCommandsTests: XCTestCase {

  // MARK: - Helpers

  private func simulator(state: FBiOSTargetState) -> FBSimulator {
    FBSimulatorTestSupport.testableSimulator(withDevice: StubStateDevice(state: state))
  }

  // MARK: - Raw process spawn options

  func testRawSpawnOptionsPrependLaunchPathAsArgv0() {
    let options = FBSimulatorProcessSpawnCommands.simDeviceLaunchOptions(
      withSimulator: simulator(state: .booted),
      launchPath: "/bin/echo",
      arguments: ["hello", "world"],
      environment: [:],
      waitForDebugger: false,
      stdOut: nil,
      stdErr: nil,
      mode: .launchd)

    XCTAssertEqual(
      options["arguments"] as? [String], ["/bin/echo", "hello", "world"],
      "SimDevice does not set argv[0], so the launch path must be prepended to the arguments")
  }

  func testRawSpawnOptionsCarryEnvironmentAndOmitWaitForDebuggerWhenFalse() {
    let options = FBSimulatorProcessSpawnCommands.simDeviceLaunchOptions(
      withSimulator: simulator(state: .booted),
      launchPath: "/bin/echo",
      arguments: [],
      environment: ["KEY": "VALUE"],
      waitForDebugger: false,
      stdOut: nil,
      stdErr: nil,
      mode: .launchd)

    XCTAssertEqual(options["environment"] as? [String: String], ["KEY": "VALUE"])
    XCTAssertNil(options["wait_for_debugger"], "wait_for_debugger must be absent when not requested")
    XCTAssertNil(options["stdout"], "No stdout key should be set when no stdout attachment is provided")
    XCTAssertNil(options["stderr"], "No stderr key should be set when no stderr attachment is provided")
  }

  func testRawSpawnOptionsSetWaitForDebuggerWhenRequested() {
    let options = FBSimulatorProcessSpawnCommands.simDeviceLaunchOptions(
      withSimulator: simulator(state: .booted),
      launchPath: "/bin/echo",
      arguments: [],
      environment: [:],
      waitForDebugger: true,
      stdOut: nil,
      stdErr: nil,
      mode: .launchd)

    XCTAssertEqual((options["wait_for_debugger"] as? NSNumber)?.intValue, 1)
  }

  func testRawSpawnOptionsStandaloneReflectsMode() {
    let booted = simulator(state: .booted)

    let launchd = FBSimulatorProcessSpawnCommands.simDeviceLaunchOptions(
      withSimulator: booted, launchPath: "/bin/echo", arguments: [], environment: [:],
      waitForDebugger: false, stdOut: nil, stdErr: nil, mode: .launchd)
    XCTAssertEqual((launchd["standalone"] as? NSNumber)?.boolValue, false)

    let posix = FBSimulatorProcessSpawnCommands.simDeviceLaunchOptions(
      withSimulator: booted, launchPath: "/bin/echo", arguments: [], environment: [:],
      waitForDebugger: false, stdOut: nil, stdErr: nil, mode: .posixSpawn)
    XCTAssertEqual((posix["standalone"] as? NSNumber)?.boolValue, true)
  }

  // MARK: - standalone resolution

  func testStandaloneIsTrueForPosixSpawnRegardlessOfState() {
    XCTAssertTrue(FBSimulatorProcessSpawnCommands.shouldLaunchStandalone(onSimulator: simulator(state: .booted), mode: .posixSpawn))
    XCTAssertTrue(FBSimulatorProcessSpawnCommands.shouldLaunchStandalone(onSimulator: simulator(state: .shutdown), mode: .posixSpawn))
  }

  func testStandaloneIsFalseForLaunchdRegardlessOfState() {
    XCTAssertFalse(FBSimulatorProcessSpawnCommands.shouldLaunchStandalone(onSimulator: simulator(state: .booted), mode: .launchd))
    XCTAssertFalse(FBSimulatorProcessSpawnCommands.shouldLaunchStandalone(onSimulator: simulator(state: .shutdown), mode: .launchd))
  }

  func testStandaloneDefaultModeFollowsBootState() {
    XCTAssertFalse(
      FBSimulatorProcessSpawnCommands.shouldLaunchStandalone(onSimulator: simulator(state: .booted), mode: .default),
      "When booted, default mode launches into launchd (not standalone)")
    XCTAssertTrue(
      FBSimulatorProcessSpawnCommands.shouldLaunchStandalone(onSimulator: simulator(state: .shutdown), mode: .default),
      "When not booted, default mode launches standalone")
  }

  // MARK: - Application launch options

  func testAppLaunchOptionsDoNotPrependLaunchPathAndCarryStdioPaths() {
    let configuration = FBApplicationLaunchConfiguration(
      bundleID: "com.example.app",
      bundleName: "App",
      arguments: ["--flag"],
      environment: ["E": "1"],
      waitForDebugger: true,
      io: FBProcessIO<AnyObject, AnyObject, AnyObject>.outputToDevNull(),
      launchMode: .failIfRunning)

    let options = FBSimulatorApplicationCommands.simDeviceLaunchOptions(
      for: configuration, stdOutPath: "relative/out", stdErrPath: "relative/err")

    XCTAssertEqual(
      options["arguments"] as? [String], ["--flag"],
      "App launch passes arguments through unchanged — unlike raw spawn, no argv[0] is prepended")
    XCTAssertEqual(options["environment"] as? [String: String], ["E": "1"])
    XCTAssertEqual((options["wait_for_debugger"] as? NSNumber)?.intValue, 1)
    XCTAssertEqual(options["stdout"] as? String, "relative/out")
    XCTAssertEqual(options["stderr"] as? String, "relative/err")
  }
}

// MARK: - Device double

/// Stands in for `SimDevice` on the unit-test path, exposing only the two selectors
/// `FBSimulator` reads here: `-UDID` (logger naming at init) and `-state`
/// (consulted by `shouldLaunchStandalone`). Passed through `id`, so a Swift class
/// suffices — it never reaches real CoreSimulator.
private final class StubStateDevice: NSObject {
  @objc(UDID) let udid = NSUUID()
  @objc let state: UInt64

  init(state: FBiOSTargetState) {
    self.state = UInt64(state.rawValue)
    super.init()
  }
}

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
/// dictionary. Mostly pure-function assertions over the option builders, so they
/// hold without a booted simulator and lock the behavior that the spawn-path
/// consolidation must preserve (argv[0] handling, `standalone` resolution, stdio keys).
/// The stdin case drives the whole launcher against a recording device double,
/// because what it records is the absence of a key rather than the value of one.
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

  // MARK: - stdin on the raw spawn path

  func testRawSpawnAcceptsAConfigurationCarryingStdIn() async throws {
    let device = RecordingSpawnDevice()
    let simulator = FBSimulatorTestSupport.testableSimulator(withDevice: device)
    let stdIn = unsafeBitCast(FBProcessInput<NSObject>.fromConsumer(), to: FBProcessInput<AnyObject>.self)
    let stdOut = FBProcessOutput<AnyObject>(for: FBNullDataConsumer())
    let configuration = FBProcessSpawnConfiguration(
      launchPath: "/bin/cat",
      arguments: [],
      environment: [:],
      io: FBProcessIO<AnyObject, AnyObject, AnyObject>(stdIn: stdIn, stdOut: stdOut, stdErr: nil),
      mode: .posixSpawn)

    // BUG: the launch is accepted and the caller's input is dropped on the floor.
    // `SimDevice`'s option dictionary carries stdout and stderr as file
    // descriptors but has no stdin key at all, so there is nowhere for the
    // attached input to go. Rejected in the following commit.
    let process = try await simulator.launchProcess(configuration)
    XCTAssertEqual(process.processIdentifier, RecordingSpawnDevice.stubbedProcessIdentifier)

    let options = try XCTUnwrap(device.spawnedOptions)
    XCTAssertNotNil(options["stdout"], "stdout reaches the child as a file descriptor")
    XCTAssertNil(options["stdin"], "but there is no key through which stdin could reach it")

    device.terminate(statLoc: 0)
    let exitCode = try await bridgeFBFuture(process.exitCode)
    XCTAssertEqual(exitCode.int32Value, 0)
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

/// Device double for the raw-spawn path. Records the option dictionary it is
/// handed, reports a fixed pid, and holds the termination callback until the
/// test fires it, so a launch can be observed end-to-end without CoreSimulator.
private final class RecordingSpawnDevice: NSObject, @unchecked Sendable {
  static let stubbedProcessIdentifier: pid_t = 4242

  @objc(UDID) let udid = NSUUID()
  @objc let state = UInt64(FBiOSTargetState.booted.rawValue)

  private(set) var spawnedOptions: [String: Any]?
  private var terminationQueue: DispatchQueue?
  private var terminationHandler: ((Int32) -> Void)?

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
    self.terminationQueue = terminationQueue
    self.terminationHandler = terminationHandler
    completionQueue.async { completionHandler(nil, Self.stubbedProcessIdentifier) }
  }

  func terminate(statLoc: Int32) {
    guard let terminationQueue, let terminationHandler else {
      return XCTFail("The device was never asked to spawn, so there is no termination handler to fire")
    }
    terminationQueue.async { terminationHandler(statLoc) }
  }
}

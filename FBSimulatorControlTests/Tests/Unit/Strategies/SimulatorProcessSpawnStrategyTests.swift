/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import XCTest

/// How `Simulator`'s spawn paths build the `SimDevice` launch-option dictionary: argv[0]
/// handling, `standalone` resolution, stdio keys. Pure-function assertions except the stdin
/// and teardown cases, which drive the launcher against device doubles.
final class SimulatorProcessSpawnStrategyTests: XCTestCase {

  private func simulator(state: TargetState) -> Simulator {
    SimulatorTestSupport.testableSimulator(withDevice: StubStateDevice(state: state))
  }

  // MARK: - Raw process spawn options

  func testRawSpawnOptionsPrependLaunchPathAsArgv0() {
    let options = SimulatorProcessSpawnStrategy.simDeviceLaunchOptions(
      withSimulator: simulator(state: .booted),
      launchPath: "/bin/echo",
      arguments: ["hello", "world"],
      environment: [:],
      waitForDebugger: false,
      standardOutput: nil,
      standardError: nil,
      mode: .launchd)

    XCTAssertEqual(
      options["arguments"] as? [String], ["/bin/echo", "hello", "world"],
      "SimDevice does not set argv[0], so the launch path must be prepended to the arguments")
  }

  func testRawSpawnOptionsCarryEnvironmentAndOmitWaitForDebuggerWhenFalse() {
    let options = SimulatorProcessSpawnStrategy.simDeviceLaunchOptions(
      withSimulator: simulator(state: .booted),
      launchPath: "/bin/echo",
      arguments: [],
      environment: ["KEY": "VALUE"],
      waitForDebugger: false,
      standardOutput: nil,
      standardError: nil,
      mode: .launchd)

    XCTAssertEqual(options["environment"] as? [String: String], ["KEY": "VALUE"])
    XCTAssertNil(options["wait_for_debugger"], "wait_for_debugger must be absent when not requested")
    XCTAssertNil(options["stdout"], "No stdout key should be set when no stdout attachment is provided")
    XCTAssertNil(options["stderr"], "No stderr key should be set when no stderr attachment is provided")
  }

  func testRawSpawnOptionsSetWaitForDebuggerWhenRequested() {
    let options = SimulatorProcessSpawnStrategy.simDeviceLaunchOptions(
      withSimulator: simulator(state: .booted),
      launchPath: "/bin/echo",
      arguments: [],
      environment: [:],
      waitForDebugger: true,
      standardOutput: nil,
      standardError: nil,
      mode: .launchd)

    XCTAssertEqual((options["wait_for_debugger"] as? NSNumber)?.intValue, 1)
  }

  func testRawSpawnOptionsStandaloneReflectsMode() {
    let booted = simulator(state: .booted)

    let launchd = SimulatorProcessSpawnStrategy.simDeviceLaunchOptions(
      withSimulator: booted, launchPath: "/bin/echo", arguments: [], environment: [:],
      waitForDebugger: false, standardOutput: nil, standardError: nil, mode: .launchd)
    XCTAssertEqual((launchd["standalone"] as? NSNumber)?.boolValue, false)

    let posix = SimulatorProcessSpawnStrategy.simDeviceLaunchOptions(
      withSimulator: booted, launchPath: "/bin/echo", arguments: [], environment: [:],
      waitForDebugger: false, standardOutput: nil, standardError: nil, mode: .posixSpawn)
    XCTAssertEqual((posix["standalone"] as? NSNumber)?.boolValue, true)
  }

  // MARK: - standalone resolution

  func testStandaloneIsTrueForPosixSpawnRegardlessOfState() {
    XCTAssertTrue(SimulatorProcessSpawnStrategy.shouldLaunchStandalone(onSimulator: simulator(state: .booted), mode: .posixSpawn))
    XCTAssertTrue(SimulatorProcessSpawnStrategy.shouldLaunchStandalone(onSimulator: simulator(state: .shutdown), mode: .posixSpawn))
  }

  func testStandaloneIsFalseForLaunchdRegardlessOfState() {
    XCTAssertFalse(SimulatorProcessSpawnStrategy.shouldLaunchStandalone(onSimulator: simulator(state: .booted), mode: .launchd))
    XCTAssertFalse(SimulatorProcessSpawnStrategy.shouldLaunchStandalone(onSimulator: simulator(state: .shutdown), mode: .launchd))
  }

  func testStandaloneDefaultModeFollowsBootState() {
    XCTAssertFalse(
      SimulatorProcessSpawnStrategy.shouldLaunchStandalone(onSimulator: simulator(state: .booted), mode: .default),
      "When booted, default mode launches into launchd (not standalone)")
    XCTAssertTrue(
      SimulatorProcessSpawnStrategy.shouldLaunchStandalone(onSimulator: simulator(state: .shutdown), mode: .default),
      "When not booted, default mode launches standalone")
  }

  // MARK: - SubprocessLauncher

  func testLauncherSpawnsTheSpecWithExactlyItsExplicitEnvironment() async throws {
    let device = ExitingSpawnDevice(statLoc: 3 << 8)
    let launcher = SimulatorSubprocessLauncher(simulator: SimulatorTestSupport.testableSimulator(withDevice: device))
    let subprocess = Subprocess(executable: "/usr/bin/true", arguments: ["-a"], environment: .additions(["E": "1"]), mode: .posixSpawn)

    let completed = try await subprocess.run(on: launcher, output: .closed, error: .closed, exitPolicy: .mustExit([3]))

    XCTAssertEqual(completed.terminationStatus, .exited(3))
    XCTAssertEqual(completed.processIdentifier, 4242)
    let options = try XCTUnwrap(device.spawnedOptions)
    XCTAssertEqual(options["arguments"] as? [String], ["/usr/bin/true", "-a"])
    // None of the host's DEVELOPER_DIR, HOME or PATH leak into the simulator.
    XCTAssertEqual(options["environment"] as? [String: String], ["E": "1"])
    XCTAssertEqual((options["standalone"] as? NSNumber)?.boolValue, true)
    XCTAssertNil(options["stdout"], "A closed stream is not handed to the device")
  }

  func testLauncherGivesAnInheritingEnvironmentNothingFromTheHost() async throws {
    let device = ExitingSpawnDevice()
    let launcher = SimulatorSubprocessLauncher(simulator: SimulatorTestSupport.testableSimulator(withDevice: device))

    _ = try await Subprocess(executable: "/usr/bin/true", environment: .inherit).run(on: launcher, output: .closed, error: .closed)

    XCTAssertEqual(device.spawnedOptions?["environment"] as? [String: String], [:])
  }

  func testLauncherDrainsStdOutBeforeTheExitResolves() async throws {
    let payload = Data(repeating: UInt8(ascii: "x"), count: 12_000) + Data("end\n".utf8)
    let device = ExitingSpawnDevice(stdOutPayload: payload)
    let launcher = SimulatorSubprocessLauncher(simulator: SimulatorTestSupport.testableSimulator(withDevice: device))
    let received = Received()
    let consumer = FBBlockDataConsumer.synchronousDataConsumer { data in
      Thread.sleep(forTimeInterval: 0.05)
      received.append(data)
    }

    let completed = try await Subprocess(executable: "/bin/echo").run(on: launcher, output: .consumer(consumer), error: .closed)

    XCTAssertEqual(completed.terminationStatus, .exited(0))
    XCTAssertEqual(received.data, payload)
  }

  func testLauncherRejectsAStandardInputWithoutReachingTheDevice() async throws {
    let device = RecordingSpawnDevice()
    let launcher = SimulatorSubprocessLauncher(simulator: SimulatorTestSupport.testableSimulator(withDevice: device))

    do {
      _ = try await Subprocess(executable: "/bin/cat").run(on: launcher, output: .closed, error: .closed, input: .data(Data("in".utf8)))
      XCTFail("Expected the launch to be rejected, but it ran")
    } catch SubprocessError.inputUnsupported(let executable) {
      XCTAssertEqual(executable, "/bin/cat")
    }

    XCTAssertNil(device.spawnedOptions)
  }

  // MARK: - Application launch options

  func testAppLaunchOptionsDoNotPrependLaunchPathAndCarryStdioPaths() {
    let configuration = ApplicationLaunchConfiguration(
      bundleID: "com.example.app",
      bundleName: "App",
      arguments: ["--flag"],
      environment: ["E": "1"],
      waitForDebugger: true,
      io: FBProcessIO<AnyObject, AnyObject, AnyObject>.outputToDevNull(),
      launchMode: .failIfRunning)

    let options = SimulatorApplicationCommands.simDeviceLaunchOptions(
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
/// `Simulator` reads here: `-UDID` (logger naming at init) and `-state`
/// (consulted by `shouldLaunchStandalone`). Passed through `id`, so a Swift class
/// suffices — it never reaches real CoreSimulator.
private final class StubStateDevice {
  @objc(UDID) let udid = NSUUID()
  @objc let state: UInt64

  init(state: TargetState) {
    self.state = UInt64(state.rawValue)
  }
}

/// Device double for the raw-spawn path. Records the option dictionary it is handed,
/// so a test can distinguish a launch that reached `SimDevice` from one rejected before
/// it. The spawn completes rather than hanging, so a regression surfaces as a failed
/// assertion rather than as a timeout.
private final class RecordingSpawnDevice: @unchecked Sendable {
  @objc(UDID) let udid = NSUUID()
  @objc let state = UInt64(TargetState.booted.rawValue)

  private(set) var spawnedOptions: [String: Any]?

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
    completionQueue.async { completionHandler(nil, 4242) }
  }
}

private final class Received: @unchecked Sendable {
  private let lock = NSLock()
  private var storage = Data()

  var data: Data {
    lock.withLock { storage }
  }

  func append(_ data: Data) {
    lock.withLock { storage.append(data) }
  }
}

/// Device double that behaves like a process which writes to stdout and exits at once: the
/// payload goes into the stdout descriptor it is handed, and termination is reported before
/// anything has read it.
private final class ExitingSpawnDevice: @unchecked Sendable {
  @objc(UDID) let udid = NSUUID()
  @objc let state = UInt64(TargetState.booted.rawValue)

  private let stdOutPayload: Data
  private let statLoc: Int32
  private(set) var spawnedOptions: [String: Any]?

  init(stdOutPayload: Data = Data(), statLoc: Int32 = 0) {
    self.stdOutPayload = stdOutPayload
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
    if let fileDescriptor = (options["stdout"] as? NSNumber)?.int32Value {
      stdOutPayload.withUnsafeBytes { _ = write(fileDescriptor, $0.baseAddress, $0.count) }
    }
    let statLoc = statLoc
    completionQueue.async {
      completionHandler(nil, 4242)
      terminationQueue.async { terminationHandler(statLoc) }
    }
  }
}

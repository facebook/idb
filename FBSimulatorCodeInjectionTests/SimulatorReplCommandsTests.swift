/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorCodeInjection
@testable import FBSimulatorControl
import XCTest

/// What the REPL injects into each host, what the simulator context spawns, and when its session is over.
final class SimulatorReplCommandsTests: XCTestCase {

  private static func isWritable(_ fileDescriptor: Any?) -> Bool {
    guard let fileDescriptor = fileDescriptor as? NSNumber else { return false }
    return fileDescriptor.int32Value >= 0
  }

  func testSpawnsTheBridgeToServeTheReplSocket() async throws {
    let device = HeldSpawnDevice()
    let commands = SimulatorReplCommands(simulator: SimulatorTestSupport.testableSimulator(withDevice: device))

    let repl = try await commands.startSimulator(bridgePath: "/bridge", libReplPath: "/libRepl.dylib", extraInterfacePaths: ["/IDB.swiftinterface"])

    XCTAssertTrue(repl.socketPath.hasPrefix("/tmp/idb_repl_"))
    XCTAssertEqual(repl.extraInterfacePaths, ["/IDB.swiftinterface"])
    let options = try XCTUnwrap(device.spawnedOptions)
    XCTAssertEqual(options["arguments"] as? [String], ["/bridge", "repl", "start", repl.socketPath, "/libRepl.dylib"])
    XCTAssertEqual(options["environment"] as? [String: String], [:])
    XCTAssertTrue(Self.isWritable(options["stdout"]), "The bridge writes to /dev/null")
    XCTAssertTrue(Self.isWritable(options["stderr"]), "The bridge writes to /dev/null")
    device.terminate(statLoc: 0)
  }

  func testLoadsAdditionalLibrariesIntoTheBridgeAfterTheShim() async throws {
    let device = HeldSpawnDevice()
    let commands = SimulatorReplCommands(simulator: SimulatorTestSupport.testableSimulator(withDevice: device))

    let repl = try await commands.startSimulator(bridgePath: "/bridge", libReplPath: "/libRepl.dylib", additionalLibraries: ["/first.dylib", "/second.dylib"], extraInterfacePaths: [])

    let options = try XCTUnwrap(device.spawnedOptions)
    XCTAssertEqual(options["arguments"] as? [String], ["/bridge", "repl", "start", repl.socketPath, "/libRepl.dylib", "/first.dylib", "/second.dylib"])
    device.terminate(statLoc: 0)
  }

  func testArmsAnAppLaunchWithTheShimThenAdditionalLibraries() async throws {
    let commands = SimulatorReplCommands(simulator: SimulatorTestSupport.testableSimulator(withDevice: HeldSpawnDevice()))

    let environment = try await commands.appLaunchEnvironment(bundleID: "com.example.App", additionalLibraries: ["/first.dylib", "/second.dylib"])

    let shim = try XCTUnwrap(BundledResources.path(forItem: "libRepl-iOS.dylib"))
    XCTAssertEqual(environment["DYLD_INSERT_LIBRARIES"], "\(shim):/first.dylib:/second.dylib")
  }

  func testSessionRunsUntilTheBridgeExits() async throws {
    let device = HeldSpawnDevice()
    let commands = SimulatorReplCommands(simulator: SimulatorTestSupport.testableSimulator(withDevice: device))

    let repl = try await commands.startSimulator(bridgePath: "/bridge", libReplPath: "/libRepl.dylib", extraInterfacePaths: [])

    guard case let .process(process) = repl.host else {
      return XCTFail("Expected the bridge process to host the session, got \(repl.host)")
    }
    XCTAssertNil(process.observedTerminationStatus, "The session is live while the bridge runs")
    device.terminate(statLoc: 1 << 8)
    try await repl.waitForHostToFinish()
  }
}

// MARK: - Device double

/// Records the spawn and holds the process running until the test reports its termination.
private final class HeldSpawnDevice: @unchecked Sendable {
  @objc(UDID) let udid = NSUUID()
  @objc let state = UInt64(TargetState.booted.rawValue)

  private let lock = NSLock()
  private var options: [String: Any]?
  private var termination: ((Int32) -> Void)?

  var spawnedOptions: [String: Any]? {
    lock.withLock { options }
  }

  func terminate(statLoc: Int32) {
    lock.withLock { termination }?(statLoc)
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
    lock.withLock {
      self.options = options
      self.termination = { statLoc in terminationQueue.async { terminationHandler(statLoc) } }
    }
    completionQueue.async { completionHandler(nil, 4242) }
  }
}

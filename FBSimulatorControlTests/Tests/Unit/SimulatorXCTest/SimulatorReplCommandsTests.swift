/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
@testable import SimulatorXCTest
import XCTest

/// What the simulator-context REPL spawns inside the simulator, and when its session is over.
final class SimulatorReplCommandsTests: XCTestCase {

  private static func isWritable(_ fileDescriptor: Any?) -> Bool {
    guard let fileDescriptor = fileDescriptor as? NSNumber else { return false }
    return fileDescriptor.int32Value >= 0
  }

  func testSpawnsTheBridgeToServeTheReplSocket() async throws {
    let device = HeldSpawnDevice()
    let commands = SimulatorReplCommands.commands(with: SimulatorTestSupport.testableSimulator(withDevice: device))

    let repl = try await commands.startSimulator(bridgePath: "/bridge", libReplPath: "/libRepl.dylib", extraInterfacePaths: ["/IDB.swiftinterface"])

    XCTAssertTrue(repl.socketPath.hasPrefix("/tmp/idb_repl_"))
    XCTAssertEqual(repl.extraInterfacePaths, ["/IDB.swiftinterface"])
    let options = try XCTUnwrap(device.spawnedOptions)
    XCTAssertEqual(options["arguments"] as? [String], ["/bridge", "repl", "start", repl.socketPath, "/libRepl.dylib"])
    XCTAssertEqual(options["environment"] as? [String: String], [:])
    XCTAssertFalse(Self.isWritable(options["stdout"]), "The bridge's output is discarded")
    XCTAssertFalse(Self.isWritable(options["stderr"]), "The bridge's output is discarded")
    device.terminate(statLoc: 0)
  }

  func testSessionRunsUntilTheBridgeExits() async throws {
    let device = HeldSpawnDevice()
    let commands = SimulatorReplCommands.commands(with: SimulatorTestSupport.testableSimulator(withDevice: device))

    let repl = try await commands.startSimulator(bridgePath: "/bridge", libReplPath: "/libRepl.dylib", extraInterfacePaths: [])

    XCTAssertFalse(repl.run.hasCompleted, "The session is live while the bridge runs")
    device.terminate(statLoc: 1 << 8)
    try await bridgeFBFutureVoid(repl.run)
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

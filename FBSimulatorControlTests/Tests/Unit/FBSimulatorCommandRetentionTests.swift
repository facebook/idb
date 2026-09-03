/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Foundation
import Testing

/// Whether resolving a command class through the target's own command cache keeps the target
/// alive.
///
/// A simulator owns its `commandCache`; the cache owns whatever is resolved into it. A command
/// class that holds its simulator strongly therefore closes a cycle — simulator to cache to
/// command to simulator — and the simulator can never be released. Most command classes hold
/// `weak var simulator` precisely to avoid this.
@Suite("Simulator command retention")
struct FBSimulatorCommandRetentionTests {

  /// Resolves a command through the cache, then reports whether the simulator survived the only
  /// strong reference to it going away.
  private func simulatorSurvives(_ resolve: (FBSimulator) throws -> Void) rethrows -> Bool {
    weak var weakSimulator: FBSimulator?
    try autoreleasepool {
      let simulator = FBSimulatorTestSupport.testableSimulator()
      weakSimulator = simulator
      try resolve(simulator)
    }
    return weakSimulator != nil
  }

  @Test("A command holding its simulator weakly lets the simulator go")
  func weaklyHeldCommandDoesNotRetainTheSimulator() throws {
    #expect(try simulatorSurvives { _ = try $0.location } == false)
  }

  /// These three hold their simulator strongly, which is only safe because they are no longer
  /// resolved through the simulator's own cache — nothing outlives the call that builds them.
  @Test("The file commands do not retain the simulator")
  func fileCommandsDoNotRetainTheSimulator() throws {
    #expect(try simulatorSurvives { _ = try $0.file } == false)
  }

  @Test("The launchctl commands do not retain the simulator")
  func launchCtlCommandsDoNotRetainTheSimulator() throws {
    #expect(try simulatorSurvives { _ = try $0.launchCtl } == false)
  }

  @Test("The DAP server commands do not retain the simulator")
  func dapServerCommandsDoNotRetainTheSimulator() throws {
    #expect(try simulatorSurvives { _ = try $0.dapServer } == false)
  }
}

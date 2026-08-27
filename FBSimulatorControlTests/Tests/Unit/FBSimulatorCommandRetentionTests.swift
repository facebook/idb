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
    #expect(try simulatorSurvives { _ = try $0.locationCommands() } == false)
  }

  // BUG: these three hold `private let simulator: FBSimulator` rather than `weak var`, so
  // resolving one into the simulator's own cache closes a retain cycle and the simulator is
  // never released — flipped in the following commit.
  @Test("The file commands retain the simulator")
  func fileCommandsRetainTheSimulator() throws {
    #expect(try simulatorSurvives { _ = try $0.fileCommands() } == true)
  }

  @Test("The launchctl commands retain the simulator")
  func launchCtlCommandsRetainTheSimulator() throws {
    #expect(try simulatorSurvives { _ = try $0.launchCtlCommands() } == true)
  }

  @Test("The DAP server commands retain the simulator")
  func dapServerCommandsRetainTheSimulator() throws {
    #expect(try simulatorSurvives { _ = try $0.dapServerCommand() } == true)
  }
}

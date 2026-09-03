/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import Foundation
import XCTest

/// A `SimDevice` stand-in that returns canned `getenv` values keyed by name.
private final class GetenvStubDevice {
  @objc let UDID = NSUUID()
  private let values: [String: String]

  init(getenvValues: [String: String]) {
    self.values = getenvValues
  }

  @objc(getenv:error:)
  func getenv(_ name: String) throws -> String {
    values[name] ?? ""
  }
}

/// Locks the testmanagerd socket-path resolution without requiring a booted simulator.
final class FBSimulatorXCTestCommandsTests: XCTestCase {

  func testTestManagerDaemonSocketPathReturnsGetenvValue() async throws {
    let simulator = FBSimulatorTestSupport.testableSimulator(withDevice: GetenvStubDevice(getenvValues: ["TESTMANAGERD_SIM_SOCK": "/tmp/testmanagerd.sock"]))
    let commands = FBSimulatorXCTestCommands.commands(with: simulator)

    let path = try await commands.testManagerDaemonSocketPath()

    XCTAssertEqual(path, "/tmp/testmanagerd.sock")
  }
}

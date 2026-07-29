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

/// A `SimDevice` stand-in that returns a canned `getenv` value, so the testmanagerd
/// socket-path poll can be exercised without a booted simulator. `FBSimulator`'s initializer
/// only reads `device.UDID.UUIDString`, so `UDID` plus `getenv:error:` is the whole surface.
private final class GetenvStubDevice: NSObject {
  @objc let UDID = NSUUID()
  private let value: String

  init(getenvValue: String) {
    self.value = getenvValue
    super.init()
  }

  @objc(getenv:error:)
  func getenv(_ name: String) throws -> String {
    value
  }
}

/// Locks the testmanagerd socket-path resolution: the async poll reads
/// `TESTMANAGERD_SIM_SOCK` from the simulator environment and returns the first non-empty value.
final class FBSimulatorXCTestCommandsTests: XCTestCase {

  func testTestManagerDaemonSocketPathReturnsGetenvValue() async throws {
    let simulator = FBSimulatorTestSupport.testableSimulator(withDevice: GetenvStubDevice(getenvValue: "/tmp/testmanagerd.sock"))
    let commands = FBSimulatorXCTestCommands.commands(with: simulator)

    let path = try await commands.testManagerDaemonSocketPath()

    XCTAssertEqual(path, "/tmp/testmanagerd.sock")
  }
}

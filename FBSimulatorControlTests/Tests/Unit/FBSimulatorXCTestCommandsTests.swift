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

/// A `SimDevice` stand-in that returns canned `getenv` values keyed by name, so the testmanagerd
/// socket-path poll can be exercised without a booted simulator. `FBSimulator`'s initializer
/// only reads `device.UDID.UUIDString`, so `UDID` plus `getenv:error:` is the whole surface.
private final class GetenvStubDevice: NSObject {
  @objc let UDID = NSUUID()
  private let values: [String: String]

  init(getenvValues: [String: String]) {
    self.values = getenvValues
    super.init()
  }

  @objc(getenv:error:)
  func getenv(_ name: String) throws -> String {
    values[name] ?? ""
  }
}

/// Locks the testmanagerd socket-path resolution: the async poll reads the socket path from the
/// simulator environment and returns the first non-empty value. The env key is parameterized so the
/// classic (`TESTMANAGERD_SIM_SOCK`) and remote-automation (`TESTMANAGERD_REMOTE_AUTOMATION_SIM_SOCK`)
/// paths resolve their own sockets through the same poll.
final class FBSimulatorXCTestCommandsTests: XCTestCase {

  func testTestManagerDaemonSocketPathReturnsGetenvValue() async throws {
    let simulator = FBSimulatorTestSupport.testableSimulator(withDevice: GetenvStubDevice(getenvValues: ["TESTMANAGERD_SIM_SOCK": "/tmp/testmanagerd.sock"]))
    let commands = FBSimulatorXCTestCommands.commands(with: simulator)

    let path = try await commands.testManagerDaemonSocketPath()

    XCTAssertEqual(path, "/tmp/testmanagerd.sock")
  }

  func testTestManagerDaemonSocketPathResolvesByEnvKey() async throws {
    // The default key and an explicit key resolve to their own distinct sockets, proving the poll
    // reads the requested env key rather than a hardcoded one.
    let device = GetenvStubDevice(getenvValues: [
      "TESTMANAGERD_SIM_SOCK": "/tmp/classic.sock",
      "TESTMANAGERD_REMOTE_AUTOMATION_SIM_SOCK": "/tmp/remote-automation.sock",
    ])
    // `FBSimulatorXCTestCommands` holds the simulator weakly, so keep a strong local reference.
    let simulator = FBSimulatorTestSupport.testableSimulator(withDevice: device)
    let commands = FBSimulatorXCTestCommands.commands(with: simulator)

    let classic = try await commands.testManagerDaemonSocketPath()
    let remote = try await commands.testManagerDaemonSocketPath(envKey: "TESTMANAGERD_REMOTE_AUTOMATION_SIM_SOCK")

    XCTAssertEqual(classic, "/tmp/classic.sock", "default key resolves the classic socket")
    XCTAssertEqual(remote, "/tmp/remote-automation.sock", "explicit key resolves the remote-automation socket")
  }
}

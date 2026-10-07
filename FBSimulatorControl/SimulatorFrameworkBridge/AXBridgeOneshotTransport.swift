/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation
import SimulatorFrameworkBridgeProtocol

struct AXBridgeOneshotTransport: AXBridgeTransport {
  private let transport: SimulatorFrameworkBridgeOneshotTransport

  init(simulator: Simulator) {
    transport = SimulatorFrameworkBridgeOneshotTransport(simulator: simulator)
  }

  init(transport: SimulatorFrameworkBridgeOneshotTransport) {
    self.transport = transport
  }

  /// A missing guest binary is raised as the persistent transport raises it, so a write that never left the
  /// host is not mistaken for one that was sent.
  func send(_ request: AXBridgeRequest) async throws -> Data {
    do {
      return try await transport.send(BridgeRequest(command: request.command)).accessibilityData()
    } catch SimulatorFrameworkBridgeError.binaryMissing {
      throw AXBridgeError.bridgeUnavailable
    }
  }
}

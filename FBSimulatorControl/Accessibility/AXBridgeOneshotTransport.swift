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
  let simulator: Simulator

  func send(_ request: AXBridgeRequest) async throws -> Data {
    try await SimulatorFrameworkBridgeOneshotTransport(simulator: simulator)
      .send(BridgeRequest(command: request.command)).accessibilityData()
  }
}

/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

struct AXBridgeOneshotTransport: AXBridgeTransport {
  let simulator: FBSimulator

  func send(_ request: AXBridgeRequest) async throws -> Data {
    guard let helperPath = simulator.frameworkBridgePath else {
      throw AXBridgeError.bridgeUnavailable
    }
    let output = try await simulator.launchProcessConsumingOutput(
      launchPath: helperPath,
      arguments: request.arguments
    )
    guard !output.stdout.isEmpty else {
      let stderr = String(data: output.stderr, encoding: .utf8) ?? ""
      throw AXBridgeError.guestFailure("exit \(output.exitCode); no output. stderr: \(stderr)")
    }
    return output.stdout
  }
}

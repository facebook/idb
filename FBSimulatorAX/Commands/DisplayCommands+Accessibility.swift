/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorControl
import Foundation

extension DisplayCommands {
  /// The accessibility identity of a display a read or action names. The lookup is cached for the simulator rather
  /// than made for one read, so the guest has `timing`'s query timeout to answer; running out is the same failure a
  /// read reports.
  func accessibilityID(
    for display: SimulatorDisplay, transport: any AXBridgeTransport, requiring capabilities: AXBridgeDisplayCapabilities = [],
    timing: SimulatorAccessibilityTiming
  ) async throws -> UInt32 {
    do {
      return try await accessibilityID(for: display, transport: transport, requiring: capabilities, receiveTimeout: timing.queryTimeout)
    } catch let AXBridgeError.guestNotAnswering(after) {
      throw AccessibilityError.serviceNotAnswering(.query(timeout: timing.queryTimeout), elapsed: after, behindAbandoned: 0)
    }
  }
}

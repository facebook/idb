/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// Owns the simulator's HID connections: made on first use, shared by every caller, and dropped
/// when the simulator changes state.
public actor SimulatorHIDCommands {

  private let input: SimulatorSharedConnection<SimulatorHID>
  /// The hinge, and rotation on a runtime that reports device motion.
  let vendorDefined: SimulatorVendorHIDTransport

  public static func commands(with simulator: Simulator) -> SimulatorHIDCommands {
    SimulatorHIDCommands(simulator: simulator)
  }

  init(simulator: Simulator?, vendorDefined: SimulatorVendorHIDTransport? = nil) {
    input = SimulatorSharedConnection { [weak simulator] in
      guard let simulator else { throw WeakTargetError.simulator }
      return try await SimulatorHID(for: simulator)
    }
    self.vendorDefined = vendorDefined ?? SimulatorVendorHIDTransport(simulator: simulator)
  }

  /// The connected HID, connecting on first use and shared with every other caller.
  public func connect() async throws -> SimulatorHID {
    try await input.connection()
  }

  /// Closes the connections, flushing what the input connection still has queued, so the next
  /// `connect()` or vendor-defined send starts afresh.
  public func disconnect() async {
    let closing = await input.reset()
    await vendorDefined.disconnect()
    if let hid = try? await closing?.value {
      await hid.close()
    }
  }
}

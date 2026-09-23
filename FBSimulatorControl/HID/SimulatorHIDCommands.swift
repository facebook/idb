/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// Owns the simulator's HID connection: made on first use, shared by every caller, and dropped
/// when the simulator changes state.
public actor SimulatorHIDCommands {

  private weak var simulator: Simulator?
  private var connection: Task<SimulatorHID, Error>?

  public static func commands(with simulator: Simulator) -> SimulatorHIDCommands {
    SimulatorHIDCommands(simulator: simulator)
  }

  private init(simulator: Simulator) {
    self.simulator = simulator
  }

  /// The connected HID, connecting on first use. Callers that arrive while a connection is being
  /// made share that attempt rather than starting their own.
  public func connect() async throws -> SimulatorHID {
    if let connection {
      return try await connection.value
    }
    guard let simulator else {
      throw WeakTargetError.simulator
    }
    let connection = Task { try await SimulatorHID(for: simulator) }
    self.connection = connection
    do {
      return try await connection.value
    } catch {
      // The actor may have been re-entered during the await, so only forget the attempt that failed.
      if self.connection == connection {
        self.connection = nil
      }
      throw error
    }
  }

  /// Closes the connection, flushing what it still has queued, so the next `connect()` starts
  /// afresh.
  public func disconnect() async {
    guard let connection else {
      return
    }
    self.connection = nil
    if let hid = try? await connection.value {
      await hid.close()
    }
  }
}

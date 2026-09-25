/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// An input connection the caller owns, as opposed to the shared one `simulator.hid.connect()` vends
/// and `Simulator.disconnect()` closes. Closing drains whatever is outstanding before disconnecting,
/// so an `.onClose` send is never torn down undelivered.
public struct SimulatorHIDSession: Sendable {
  public let hid: SimulatorHID

  /// `transport` forces a HID path; `nil` negotiates one. Throws if the transport cannot be
  /// established (registration may need to occur prior to booting).
  public static func open(
    _ simulator: Simulator, transport: SimulatorHIDTransportType? = nil
  ) async throws -> SimulatorHIDSession {
    SimulatorHIDSession(hid: try await SimulatorHID(for: simulator, transport: transport))
  }

  /// Drains, even when the caller is cancelled, then disconnects. Drain errors do not prevent
  /// disconnection.
  public func close() async {
    await hid.close()
  }

  /// Runs `body` with a session that is closed however `body` exits.
  public static func with<T>(
    _ simulator: Simulator,
    transport: SimulatorHIDTransportType? = nil,
    isolation: isolated (any Actor)? = #isolation,
    _ body: (SimulatorHID) async throws -> T
  ) async throws -> T {
    let session = try await open(simulator, transport: transport)
    do {
      let result = try await body(session.hid)
      await session.close()
      return result
    } catch {
      await session.close()
      throw error
    }
  }
}

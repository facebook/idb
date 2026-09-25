/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

/// The transport for vendor-defined HID reports: the hinge slider and the orientation picker of a
/// simulator whose runtime reports device motion. `dtuhidd` serves them on a service of their own,
/// beside the digitizer, so this is a second DTUHID connection rather than a second use of the
/// first.
///
/// Established on first use, since most simulators never send one, and then kept so a rotation or
/// hinge change costs a send rather than a connect, a liveness probe and a disconnect. A connection
/// that could not be established is attempted again on the next send.
///
/// One per simulator, owned by `simulator.hid` and dropped with its input connection when the
/// simulator changes state, since a connection made before a reboot is dead.
actor SimulatorVendorHIDTransport {
  typealias Connect = @Sendable () async throws -> SimulatorDTUHIDConnection

  static let serviceName = "com.apple.coredevice.feature.remote.hid.vendordefined"

  private let connect: Connect
  private var connecting: Task<SimulatorDTUHIDConnection, Error>?

  init(simulator: Simulator?) {
    self.init { [weak simulator] in
      guard let simulator else { throw WeakTargetError.simulator }
      return try await SimulatorDTUHIDConnection.connect(to: simulator, serviceName: Self.serviceName)
    }
  }

  init(connect: @escaping Connect) {
    self.connect = connect
  }

  /// Sends one report and drains it, so the guest has acted on it when this returns.
  func send(_ event: IndigoVendorDefinedEvent) async throws {
    let connection = try await established()
    try await connection.send(messageType: "IndigoVendorDefinedEvent", payload: event)
    try await connection.flush()
  }

  /// Tears down the connection, if one was ever established.
  func disconnect() async {
    guard let connecting else { return }
    self.connecting = nil
    (try? await connecting.value)?.disconnect()
  }

  /// Concurrent first sends share one connection attempt rather than racing to open two.
  private func established() async throws -> SimulatorDTUHIDConnection {
    if let connecting {
      return try await connecting.value
    }
    let attempt = Task { try await connect() }
    connecting = attempt
    do {
      return try await attempt.value
    } catch {
      if connecting == attempt { connecting = nil }
      throw error
    }
  }
}

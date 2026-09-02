/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

extension FBAMDevice {

  /// Starts a service on the device, tearing the connection down when the context is exited.
  ///
  /// The Objective-C `startService:` forwards here. Two lifetimes are in play and they are not the
  /// same: the AMDevice *session* is released as soon as the service has started — that is what the
  /// predecessor's `pop:` did, and `FBAMDevice.h` explains at length why it must not be held for
  /// the duration — while the service *connection* is invalidated when the caller finishes with it.
  @objc(startServiceConnection:)
  public func startServiceConnection(_ service: String) -> FBFutureContext<FBAMDServiceConnection> {
    let logger = self.logger
    return fbFutureFromAsync { try await self.openServiceConnection(service) }
      .onQueue(
        workQueue,
        contextualTeardown: { (connection: FBAMDServiceConnection, _: FBFutureState) -> FBFuture<NSNull> in
          Self.invalidate(connection, service: service, logger: logger)
          return FBFuture<NSNull>.empty()
        }
      ).retyped(FBFutureContext<FBAMDServiceConnection>.self)
  }

  /// Starts a service on the device, invalidating the connection once `body` returns or throws.
  ///
  /// The async counterpart of `startServiceConnection`, with the same two lifetimes: the AMDevice
  /// session is released as soon as the service has started, the connection when `body` is done.
  public func withServiceConnection<T>(
    _ service: String,
    _ body: (FBAMDServiceConnection) async throws -> T
  ) async throws -> T {
    let connection = try await openServiceConnection(service)
    defer { Self.invalidate(connection, service: service, logger: logger) }
    return try await body(connection)
  }

  /// Starts a device link service, invalidating the connection once `body` returns or throws.
  ///
  /// The device link handshake is performed before `body` runs, so the client it receives is ready
  /// to process messages.
  public func withDeviceLinkClient<T>(
    _ service: String,
    _ body: (FBDeviceLinkClient) async throws -> T
  ) async throws -> T {
    try await withServiceConnection(service) { connection in
      let client = try await FBDeviceLinkClient.deviceLinkClientAsync(connection: connection)
      return try await body(client)
    }
  }

  /// Starts a service and wraps it in an AFC client, tearing both down once `body` returns or
  /// throws.
  ///
  /// The AFC connection carries its own teardown on top of the service connection's, so the two
  /// are released innermost first.
  public func withAFCConnection<T>(
    _ service: String,
    calls afcCalls: AFCCalls = FBAFCConnection.defaultCalls,
    _ body: (FBAFCConnection) async throws -> T
  ) async throws -> T {
    let logger = self.logger
    let workQueue = self.workQueue
    return try await withServiceConnection(service) { connection in
      try await withFBFutureContext(
        FBAFCConnection.afc(from: connection, calls: afcCalls, logger: logger, queue: workQueue)
      ) { afc in
        try await body(afc)
      }
    }
  }

  // MARK: - Private

  private func openServiceConnection(_ service: String) async throws -> FBAMDServiceConnection {
    let calls = self.calls
    let logger = self.logger
    return try await withFBFutureContext(connectToDevice(withPurpose: "start_service_\(service)")) { device in
      try Self.startService(service, on: device, calls: calls, logger: logger)
    }
  }

  private static func startService(
    _ service: String,
    on connectedDevice: any FBDeviceCommands,
    calls: AMDCalls,
    logger: any FBControlCoreLogger
  ) throws -> FBAMDServiceConnection {
    logger.log("Starting service \(service)")
    let userInfo: [String: Any] = ["CloseOnInvalidate": 1, "InvalidateOnDetach": 1]
    var serviceConnection: Unmanaged<CFTypeRef>?
    let status =
      calls.SecureStartService?(
        connectedDevice.amDeviceRef,
        service as CFString,
        userInfo as CFDictionary,
        &serviceConnection
      ) ?? -1
    guard status == 0 else {
      let message = calls.CopyErrorText?(status)?.takeRetainedValue() as String? ?? "Unknown error"
      throw FBAMDeviceServiceError.secureStartServiceFailed(service: service, status: status, message: message)
    }
    guard let amDeviceRef = connectedDevice.amDeviceRef, let serviceConnection else {
      throw FBAMDeviceServiceError.deviceNotConnected(service: service)
    }
    // Unretained, matching the predecessor: the raw reference was handed straight to the
    // connection, which owns it from here.
    let connection = FBAMDServiceConnection(
      name: service,
      connection: serviceConnection.takeUnretainedValue(),
      device: amDeviceRef,
      calls: calls,
      logger: logger)
    logger.log("Service \(service) started")
    return connection
  }

  private static func invalidate(
    _ connection: FBAMDServiceConnection?,
    service: String,
    logger: any FBControlCoreLogger
  ) {
    guard let connection else {
      return
    }
    logger.log("Invalidating service \(service)")
    do {
      try connection.invalidate()
      logger.log("Invalidated service \(service)")
    } catch {
      logger.log("Failed to invalidate service \(service) with error \(error)")
    }
  }
}

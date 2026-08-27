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
    let calls = self.calls
    let logger = self.logger
    let workQueue = self.workQueue
    return
      connectToDevice(withPurpose: "start_service_\(service)")
      .onQueue(
        workQueue,
        pop: { (connectedDevice: any FBDeviceCommands) -> FBFuture<AnyObject> in
          do {
            let connection = try Self.startService(
              service, on: connectedDevice, calls: calls, logger: logger)
            return FBFuture(result: connection as AnyObject)
          } catch {
            return FBFuture(error: error)
          }
        }
      )
      .onQueue(
        workQueue,
        contextualTeardown: { (connection: AnyObject, _: FBFutureState) -> FBFuture<NSNull> in
          Self.invalidate(connection as? FBAMDServiceConnection, service: service, logger: logger)
          return FBFuture<NSNull>.empty()
        }
      ).retyped(FBFutureContext<FBAMDServiceConnection>.self)
  }

  // MARK: - Private

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

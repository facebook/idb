/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

/// The ways house-arrest service management can fail, as data rather than assembled strings.
enum FBAMDeviceServiceError: Error {
  case houseArrestStartFailed(bundleID: String, status: Int32, message: String)
  case houseArrestConnectionMissing(bundleID: String)
  case notAnAFCConnection(context: String)
  case secureStartServiceFailed(service: String, status: Int32, message: String)
  case deviceNotConnected(service: String)
  case notAMDeviceBacked(service: String)
}

extension FBAMDeviceServiceError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case let .houseArrestStartFailed(bundleID, status, message):
      return "Failed to start house_arrest service for '\(bundleID)' with error 0x\(String(status, radix: 16)) (\(message))"
    case let .houseArrestConnectionMissing(bundleID):
      return "No house_arrest connection was returned for '\(bundleID)'"
    case let .notAnAFCConnection(context):
      return "\(context) is not an FBAFCConnection"
    case let .secureStartServiceFailed(service, status, message):
      return "SecureStartService of \(service) Failed with 0x\(String(status, radix: 16)) \(message)"
    case let .deviceNotConnected(service):
      return "Cannot start service \(service): device is not connected"
    case let .notAMDeviceBacked(service):
      return "Cannot start service \(service): the device is not AMDevice backed"
    }
  }
}

private class FBAMDeviceServiceManager_HouseArrest: NSObject, FBFutureContextManagerDelegate {
  weak var device: FBAMDevice?
  let bundleID: String
  let afcCalls: AFCCalls
  var contextPoolTimeout: NSNumber?

  init(device: FBAMDevice, bundleID: String, calls: AFCCalls, serviceTimeout: NSNumber?) {
    self.device = device
    self.bundleID = bundleID
    self.afcCalls = calls
    self.contextPoolTimeout = serviceTimeout
    super.init()
  }

  func prepare(_ logger: any FBControlCoreLogger) -> FBFuture<AnyObject> {
    guard let device else {
      return FBFuture(error: FBDeviceNilError.deviceNil)
    }
    var afcConnection: Unmanaged<AnyObject>?
    logger.log("Starting house arrest for '\(bundleID)'")
    let status =
      device.calls.CreateHouseArrestService?(
        device.amDeviceRef,
        bundleID as CFString,
        nil,
        &afcConnection
      ) ?? -1
    if status != 0 {
      let internalMessage = device.calls.CopyErrorText?(status)?.takeRetainedValue() as String? ?? "unknown"
      return FBFuture(error: FBAMDeviceServiceError.houseArrestStartFailed(bundleID: bundleID, status: status, message: internalMessage))
    }
    guard let afcConnection else {
      return FBFuture(error: FBAMDeviceServiceError.houseArrestConnectionMissing(bundleID: bundleID))
    }
    let connection = FBAFCConnection(connection: afcConnection.takeUnretainedValue(), calls: afcCalls, logger: logger)
    return FBFuture(result: connection as AnyObject)
  }

  func teardown(_ context: Any, logger: any FBControlCoreLogger) -> FBFuture<NSNull> {
    guard let connection = context as? FBAFCConnection else {
      return FBFuture(error: FBAMDeviceServiceError.notAnAFCConnection(context: String(describing: context)))
    }
    logger.log("Closing connection to House Arrest for '\(bundleID)'")
    do {
      try connection.close()
      logger.log("Closed House Arrest service for '\(bundleID)'")
      return FBFuture<NSNull>.empty()
    } catch {
      logger.log("Failed to close House Arrest for '\(bundleID)' with error \(error)")
      return FBFuture(error: error)
    }
  }

  var contextName: String {
    "house_arrest_\(bundleID)"
  }

  var isContextSharable: Bool {
    false
  }
}

public class FBAMDeviceServiceManager: NSObject {
  private weak var device: FBAMDevice?
  private let serviceTimeout: NSNumber?
  private var houseArrestManagers: [String: FBFutureContextManager<FBAFCConnection>] = [:]
  private var houseArrestDelegates: [String: FBAMDeviceServiceManager_HouseArrest] = [:]

  // MARK: Initializers

  public class func manager(withAMDevice device: FBAMDevice, serviceTimeout: NSNumber?) -> FBAMDeviceServiceManager {
    FBAMDeviceServiceManager(device: device, serviceTimeout: serviceTimeout)
  }

  private init(device: FBAMDevice, serviceTimeout: NSNumber?) {
    self.device = device
    self.serviceTimeout = serviceTimeout
    super.init()
  }

  // MARK: Public Services

  public func houseArrestAFCConnection(forBundleID bundleID: String, afcCalls: AFCCalls) -> FBFutureContextManager<FBAFCConnection> {
    if let manager = houseArrestManagers[bundleID] {
      return manager
    }
    guard let device else {
      preconditionFailure("Device is nil when creating house arrest connection for '\(bundleID)'")
    }
    let delegate = FBAMDeviceServiceManager_HouseArrest(device: device, bundleID: bundleID, calls: afcCalls, serviceTimeout: serviceTimeout)
    let manager = FBFutureContextManager<FBAFCConnection>(queue: device.workQueue, delegate: delegate, logger: device.logger)
    houseArrestManagers[bundleID] = manager
    houseArrestDelegates[bundleID] = delegate
    return manager
  }
}

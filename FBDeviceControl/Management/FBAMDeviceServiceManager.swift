/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

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
      return FBDeviceControlError.describe("Device is nil").failFuture()
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
      return FBDeviceControlError.describe("Failed to start house_arrest service for '\(bundleID)' with error 0x\(String(status, radix: 16)) (\(internalMessage))").failFuture()
    }
    let connection = FBAFCConnection(connection: afcConnection!.takeUnretainedValue(), calls: afcCalls, logger: logger)
    return FBFuture(result: connection as AnyObject)
  }

  func teardown(_ context: Any, logger: any FBControlCoreLogger) -> FBFuture<NSNull> {
    let connection = context as! FBAFCConnection
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
    return "house_arrest_\(bundleID)"
  }

  var isContextSharable: Bool {
    return false
  }
}

@objc(FBAMDeviceServiceManager)
public class FBAMDeviceServiceManager: NSObject {
  private weak var device: FBAMDevice?
  private let serviceTimeout: NSNumber?
  private var houseArrestManagers: [String: FBFutureContextManager<FBAFCConnection>] = [:]
  private var houseArrestDelegates: [String: FBAMDeviceServiceManager_HouseArrest] = [:]

  // MARK: Initializers

  @objc(managerWithAMDevice:serviceTimeout:)
  public class func manager(withAMDevice device: FBAMDevice, serviceTimeout: NSNumber?) -> FBAMDeviceServiceManager {
    return FBAMDeviceServiceManager(device: device, serviceTimeout: serviceTimeout)
  }

  private init(device: FBAMDevice, serviceTimeout: NSNumber?) {
    self.device = device
    self.serviceTimeout = serviceTimeout
    super.init()
  }

  // MARK: Public Services

  @objc(houseArrestAFCConnectionForBundleID:afcCalls:)
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

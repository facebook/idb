/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

public final class FBDeviceSet: FBiOSTargetSet, FBiOSTargetSetDelegate, CustomStringConvertible {
  // Loaded once per process; a failed load is cached and rethrown by every init rather than
  // aborting the process.
  private static let _amDeviceCalls: Result<AMDCalls, Error> = Result {
    let loader = FBDeviceControlFrameworkLoader()
    try loader.loadPrivateFrameworks(FBControlCoreGlobalConfiguration.defaultLogger)
    return try loader.amDeviceCalls
  }

  private let amDeviceManager: FBAMDeviceManager
  private let restorableDeviceManager: FBAMRestorableDeviceManager
  private let storage: FBDeviceStorage<FBDevice>
  public let logger: any FBControlCoreLogger
  public weak var delegate: (any FBiOSTargetSetDelegate)?

  // MARK: Initializers

  public convenience init(logger: any FBControlCoreLogger, delegate: (any FBiOSTargetSetDelegate)?, ecidFilter: String?) throws {
    let calls = try Self._amDeviceCalls.get()
    let workQueue = DispatchQueue.main
    let asyncQueue = DispatchQueue.global(qos: .userInitiated)
    let amDeviceManager = FBAMDeviceManager(calls: calls, work: workQueue, asyncQueue: asyncQueue, ecidFilter: ecidFilter, logger: logger)
    let restorableDeviceManager = FBAMRestorableDeviceManager(calls: calls, work: workQueue, asyncQueue: asyncQueue, ecidFilter: ecidFilter, logger: logger)
    self.init(amDeviceManager: amDeviceManager, restorableDeviceManager: restorableDeviceManager, logger: logger, delegate: delegate)
    try amDeviceManager.startListening()
    try restorableDeviceManager.startListening()
  }

  private init(amDeviceManager: FBAMDeviceManager, restorableDeviceManager: FBAMRestorableDeviceManager, logger: any FBControlCoreLogger, delegate: (any FBiOSTargetSetDelegate)?) {
    self.amDeviceManager = amDeviceManager
    self.restorableDeviceManager = restorableDeviceManager
    self.logger = logger
    self.delegate = delegate
    self.storage = FBDeviceStorage<FBDevice>(logger: logger)
    subscribeToDeviceNotifications()
  }

  deinit {
    unsubscribeFromDeviceNotifications()
  }

  // MARK: CustomStringConvertible

  public var description: String {
    "FBDeviceSet: \(FBCollectionInformation.oneLineDescription(from: allDevices))"
  }

  // MARK: Querying

  public func target(withUDID udid: String) -> (any FBiOSTargetInfo)? {
    deviceWithUDID(udid)
  }

  public func deviceWithUDID(_ udid: String) -> FBDevice? {
    allDevices.first { $0.udid == udid }
  }

  // MARK: FBiOSTargetSet

  public var allTargetInfos: [any FBiOSTargetInfo] {
    allDevices
  }

  // MARK: Properties

  public var allDevices: [FBDevice] {
    Array(storage.attached.values).sorted { $0.uniqueIdentifier < $1.uniqueIdentifier }
  }

  // MARK: Private

  private func subscribeToDeviceNotifications() {
    amDeviceManager.delegate = self
    restorableDeviceManager.delegate = self
    for amDevice in amDeviceManager.currentDeviceList {
      targetAdded(amDevice, in: amDeviceManager)
    }
    for restorableDevice in restorableDeviceManager.currentDeviceList {
      targetAdded(restorableDevice, in: restorableDeviceManager)
    }
  }

  private func unsubscribeFromDeviceNotifications() {
    amDeviceManager.delegate = nil
    restorableDeviceManager.delegate = nil
  }

  private func amDeviceAdded(_ amDevice: FBAMDevice) {
    if let device = storage.device(forKey: amDevice.uniqueIdentifier) {
      device.amDevice = amDevice
    } else {
      let device = FBDevice(set: self, amDevice: amDevice, restorableDevice: nil, logger: logger)
      storage.deviceAttached(device, forKey: amDevice.uniqueIdentifier)
    }
    if let device = storage.device(forKey: amDevice.uniqueIdentifier) {
      delegate?.targetAdded(device, in: self)
    }
  }

  private func amDeviceRemoved(_ amDevice: FBAMDevice) {
    guard let device = storage.device(forKey: amDevice.uniqueIdentifier) else {
      logger.log("\(amDevice) was removed, but there's no active device for it")
      return
    }
    device.amDevice = nil
    if device.restorableDevice != nil {
      delegate?.targetUpdated(device, in: self)
    } else {
      storage.deviceDetached(forKey: amDevice.uniqueIdentifier)
      delegate?.targetRemoved(device, in: self)
    }
  }

  private func restorableDeviceAdded(_ restorableDevice: FBAMRestorableDevice) {
    if let device = storage.device(forKey: restorableDevice.uniqueIdentifier) {
      device.restorableDevice = restorableDevice
    } else {
      let device = FBDevice(set: self, amDevice: nil, restorableDevice: restorableDevice, logger: logger)
      storage.deviceAttached(device, forKey: restorableDevice.uniqueIdentifier)
    }
    if let device = storage.device(forKey: restorableDevice.uniqueIdentifier) {
      delegate?.targetAdded(device, in: self)
    }
  }

  private func restorableDeviceRemoved(_ restorableDevice: FBAMRestorableDevice) {
    guard let device = storage.device(forKey: restorableDevice.uniqueIdentifier) else {
      logger.log("\(restorableDevice) was removed, but there's no active device for it")
      return
    }
    device.restorableDevice = nil
    if device.amDevice != nil {
      delegate?.targetUpdated(device, in: self)
    } else {
      storage.deviceDetached(forKey: restorableDevice.uniqueIdentifier)
      delegate?.targetRemoved(device, in: self)
    }
  }

  // MARK: FBiOSTargetSetDelegate

  public func targetAdded(_ targetInfo: any FBiOSTargetInfo, in targetSet: any FBiOSTargetSet) {
    if let amDevice = targetInfo as? FBAMDevice {
      amDeviceAdded(amDevice)
    } else if let restorableDevice = targetInfo as? FBAMRestorableDevice {
      restorableDeviceAdded(restorableDevice)
    } else {
      logger.log("Ignoring \(targetInfo) as it is not a valid target type")
    }
  }

  public func targetRemoved(_ targetInfo: any FBiOSTargetInfo, in targetSet: any FBiOSTargetSet) {
    if let amDevice = targetInfo as? FBAMDevice {
      amDeviceRemoved(amDevice)
    } else if let restorableDevice = targetInfo as? FBAMRestorableDevice {
      restorableDeviceRemoved(restorableDevice)
    } else {
      logger.log("Ignoring \(targetInfo) as it is not a valid target type")
    }
  }

  public func targetUpdated(_ targetInfo: any FBiOSTargetInfo, in targetSet: any FBiOSTargetSet) {
    guard let device = storage.device(forKey: targetInfo.uniqueIdentifier) else {
      assertionFailure("No existing device to update for \(targetInfo)")
      return
    }
    if let amDevice = targetInfo as? FBAMDevice {
      device.amDevice = amDevice
    } else if let restorableDevice = targetInfo as? FBAMRestorableDevice {
      device.restorableDevice = restorableDevice
    } else {
      assertionFailure("No existing device to update for \(targetInfo)")
      return
    }
    delegate?.targetUpdated(device, in: self)
  }
}

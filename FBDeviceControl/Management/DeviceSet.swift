/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

public final class DeviceSet: TargetSet, TargetSetDelegate, CustomStringConvertible {
  // Loaded once per process; a failed load is cached and rethrown by every init rather than
  // aborting the process.
  private static let _amDeviceCalls: Result<AMDCalls, Error> = Result {
    let loader = DeviceControlFrameworkLoader()
    try loader.loadPrivateFrameworks(ControlCoreGlobalConfiguration.defaultLogger)
    return try loader.amDeviceCalls
  }

  private let amDeviceManager: AMDeviceManager
  private let restorableDeviceManager: AMRestorableDeviceManager
  private let storage: DeviceStorage<Device>
  public let logger: any ControlCoreLogger
  public weak var delegate: (any TargetSetDelegate)?

  public convenience init(logger: any ControlCoreLogger, delegate: (any TargetSetDelegate)?, ecidFilter: String?) throws {
    let calls = try Self._amDeviceCalls.get()
    let workQueue = DispatchQueue.main
    let asyncQueue = DispatchQueue.global(qos: .userInitiated)
    let amDeviceManager = AMDeviceManager(calls: calls, work: workQueue, asyncQueue: asyncQueue, ecidFilter: ecidFilter, logger: logger)
    let restorableDeviceManager = AMRestorableDeviceManager(calls: calls, work: workQueue, asyncQueue: asyncQueue, ecidFilter: ecidFilter, logger: logger)
    self.init(amDeviceManager: amDeviceManager, restorableDeviceManager: restorableDeviceManager, logger: logger, delegate: delegate)
    try amDeviceManager.startListening()
    try restorableDeviceManager.startListening()
  }

  private init(amDeviceManager: AMDeviceManager, restorableDeviceManager: AMRestorableDeviceManager, logger: any ControlCoreLogger, delegate: (any TargetSetDelegate)?) {
    self.amDeviceManager = amDeviceManager
    self.restorableDeviceManager = restorableDeviceManager
    self.logger = logger
    self.delegate = delegate
    self.storage = DeviceStorage<Device>(logger: logger)
    subscribeToDeviceNotifications()
  }

  deinit {
    unsubscribeFromDeviceNotifications()
  }

  public var description: String {
    "DeviceSet: \(CollectionInformation.oneLineDescription(from: allDevices))"
  }

  // MARK: - Querying

  public func target(withUDID udid: String) -> (any TargetInfo)? {
    deviceWithUDID(udid)
  }

  public func deviceWithUDID(_ udid: String) -> Device? {
    allDevices.first { $0.udid == udid }
  }

  public var allTargetInfos: [any TargetInfo] {
    allDevices
  }

  public var allDevices: [Device] {
    Array(storage.attached.values).sorted { $0.uniqueIdentifier < $1.uniqueIdentifier }
  }

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

  private func amDeviceAdded(_ amDevice: MobileDevice) {
    if let device = storage.device(forKey: amDevice.uniqueIdentifier) {
      device.amDevice = amDevice
    } else {
      let device = Device(set: self, amDevice: amDevice, restorableDevice: nil, logger: logger)
      storage.deviceAttached(device, forKey: amDevice.uniqueIdentifier)
    }
    if let device = storage.device(forKey: amDevice.uniqueIdentifier) {
      delegate?.targetAdded(device, in: self)
    }
  }

  private func amDeviceRemoved(_ amDevice: MobileDevice) {
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

  private func restorableDeviceAdded(_ restorableDevice: RestorableDevice) {
    if let device = storage.device(forKey: restorableDevice.uniqueIdentifier) {
      device.restorableDevice = restorableDevice
    } else {
      let device = Device(set: self, amDevice: nil, restorableDevice: restorableDevice, logger: logger)
      storage.deviceAttached(device, forKey: restorableDevice.uniqueIdentifier)
    }
    if let device = storage.device(forKey: restorableDevice.uniqueIdentifier) {
      delegate?.targetAdded(device, in: self)
    }
  }

  private func restorableDeviceRemoved(_ restorableDevice: RestorableDevice) {
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

  // MARK: - TargetSetDelegate

  public func targetAdded(_ targetInfo: any TargetInfo, in targetSet: any TargetSet) {
    if let amDevice = targetInfo as? MobileDevice {
      amDeviceAdded(amDevice)
    } else if let restorableDevice = targetInfo as? RestorableDevice {
      restorableDeviceAdded(restorableDevice)
    } else {
      logger.log("Ignoring \(targetInfo) as it is not a valid target type")
    }
  }

  public func targetRemoved(_ targetInfo: any TargetInfo, in targetSet: any TargetSet) {
    if let amDevice = targetInfo as? MobileDevice {
      amDeviceRemoved(amDevice)
    } else if let restorableDevice = targetInfo as? RestorableDevice {
      restorableDeviceRemoved(restorableDevice)
    } else {
      logger.log("Ignoring \(targetInfo) as it is not a valid target type")
    }
  }

  public func targetUpdated(_ targetInfo: any TargetInfo, in targetSet: any TargetSet) {
    guard let device = storage.device(forKey: targetInfo.uniqueIdentifier) else {
      assertionFailure("No existing device to update for \(targetInfo)")
      return
    }
    if let amDevice = targetInfo as? MobileDevice {
      device.amDevice = amDevice
    } else if let restorableDevice = targetInfo as? RestorableDevice {
      device.restorableDevice = restorableDevice
    } else {
      assertionFailure("No existing device to update for \(targetInfo)")
      return
    }
    delegate?.targetUpdated(device, in: self)
  }
}

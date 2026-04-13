// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

@preconcurrency import FBControlCore
import Foundation

@objc(FBDeviceSet)
public class FBDeviceSet: NSObject, FBiOSTargetSet, FBiOSTargetSetDelegate {
  private static let _ensureFrameworksLoaded: Void = {
    FBDeviceControlFrameworkLoader().loadPrivateFrameworksOrAbort()
  }()

  private let amDeviceManager: FBAMDeviceManager
  private let restorableDeviceManager: FBAMRestorableDeviceManager
  private let storage: _FBDeviceStorageBase
  @objc public let logger: any FBControlCoreLogger
  @objc public weak var delegate: (any FBiOSTargetSetDelegate)?

  // MARK: Initializers

  @objc(setWithLogger:delegate:ecidFilter:error:)
  public convenience init(logger: any FBControlCoreLogger, delegate: (any FBiOSTargetSetDelegate)?, ecidFilter: String?) throws {
    Self._ensureFrameworksLoaded
    let calls = FBDeviceControlFrameworkLoader.amDeviceCalls
    let workQueue = DispatchQueue.main
    let asyncQueue = DispatchQueue.global(qos: .userInitiated)
    let amDeviceManager = FBAMDeviceManager(calls: calls, work: workQueue, asyncQueue: asyncQueue, ecidFilter: ecidFilter ?? "", logger: logger)
    let restorableDeviceManager = FBAMRestorableDeviceManager(calls: calls, work: workQueue, asyncQueue: asyncQueue, ecidFilter: ecidFilter ?? "", logger: logger)
    self.init(amDeviceManager: amDeviceManager, restorableDeviceManager: restorableDeviceManager, logger: logger, delegate: delegate)
    try amDeviceManager.startListening()
    try restorableDeviceManager.startListening()
  }

  private init(amDeviceManager: FBAMDeviceManager, restorableDeviceManager: FBAMRestorableDeviceManager, logger: any FBControlCoreLogger, delegate: (any FBiOSTargetSetDelegate)?) {
    self.amDeviceManager = amDeviceManager
    self.restorableDeviceManager = restorableDeviceManager
    self.logger = logger
    self.delegate = delegate
    self.storage = _FBDeviceStorageBase(logger: logger)
    super.init()
    subscribeToDeviceNotifications()
  }

  deinit {
    unsubscribeFromDeviceNotifications()
  }

  // MARK: NSObject

  public override var description: String {
    return "FBDeviceSet: \(FBCollectionInformation.oneLineDescription(from: allDevices))"
  }

  // MARK: Querying

  @objc(targetWithUDID:)
  public func target(withUDID udid: String) -> (any FBiOSTargetInfo)? {
    return deviceWithUDID(udid)
  }

  @objc public func deviceWithUDID(_ udid: String) -> FBDevice? {
    return allDevices.first { $0.udid == udid }
  }

  // MARK: FBiOSTargetSet

  @objc public var allTargetInfos: [any FBiOSTargetInfo] {
    return allDevices
  }

  // MARK: Properties

  @objc public var allDevices: [FBDevice] {
    return (storage.attached.values.compactMap { $0 as? FBDevice }).sorted { $0.uniqueIdentifier < $1.uniqueIdentifier }
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
    if let device = storage.device(forKey: amDevice.uniqueIdentifier) as? FBDevice {
      device.amDevice = amDevice
    } else {
      let device = FBDevice(set: self, amDevice: amDevice, restorableDevice: nil, logger: logger)
      storage.deviceAttached(device, forKey: amDevice.uniqueIdentifier)
    }
    if let device = storage.device(forKey: amDevice.uniqueIdentifier) as? FBDevice {
      delegate?.targetAdded(device, in: self)
    }
  }

  private func amDeviceRemoved(_ amDevice: FBAMDevice) {
    guard let device = storage.device(forKey: amDevice.uniqueIdentifier) as? FBDevice else {
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
    if let device = storage.device(forKey: restorableDevice.uniqueIdentifier) as? FBDevice {
      device.restorableDevice = restorableDevice
    } else {
      let device = FBDevice(set: self, amDevice: nil, restorableDevice: restorableDevice, logger: logger)
      storage.deviceAttached(device, forKey: restorableDevice.uniqueIdentifier)
    }
    if let device = storage.device(forKey: restorableDevice.uniqueIdentifier) as? FBDevice {
      delegate?.targetAdded(device, in: self)
    }
  }

  private func restorableDeviceRemoved(_ restorableDevice: FBAMRestorableDevice) {
    guard let device = storage.device(forKey: restorableDevice.uniqueIdentifier) as? FBDevice else {
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
    guard let device = storage.device(forKey: targetInfo.uniqueIdentifier) as? FBDevice else {
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

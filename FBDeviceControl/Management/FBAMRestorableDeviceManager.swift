/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

private func notificationTypeDescription(_ status: AMRestorableDeviceNotificationType) -> String {
  switch status {
  case .connected:
    return "connected"
  case .disconnected:
    return "disconnected"
  @unknown default:
    return "unknown"
  }
}

/// The C callback MobileDevice delivers restorable device notifications to.
///
/// A C function cannot capture, so the manager travels as the context pointer that
/// `startListening` registers. It is bridged back unretained: the registration holds the only
/// retain, and gives it back when it is torn down.
private func restorableDeviceListenerCallback(
  _ device: AMRestorableDevice?,
  _ status: AMRestorableDeviceNotificationType,
  _ context: UnsafeMutableRawPointer?
) {
  guard let device, let context else {
    return
  }
  let manager = Unmanaged<FBAMRestorableDeviceManager>.fromOpaque(context).takeUnretainedValue()
  manager.handleNotification(device: device, status: status)
}

/// Obtains `FBAMRestorableDevice` instances.
@objc(FBAMRestorableDeviceManager)
public final class FBAMRestorableDeviceManager: FBDeviceManager<FBAMRestorableDevice> {

  // MARK: - Properties

  private let calls: AMDCalls
  private let workQueue: DispatchQueue
  private let asyncQueue: DispatchQueue
  private let ecidFilter: String?
  private var registrationID: Int32 = 0
  private var notificationContext: UnsafeMutableRawPointer?

  // MARK: - Initializers

  public init(
    calls: AMDCalls,
    work workQueue: DispatchQueue,
    asyncQueue: DispatchQueue,
    ecidFilter: String?,
    logger: any FBControlCoreLogger
  ) {
    self.calls = calls
    self.workQueue = workQueue
    self.asyncQueue = asyncQueue
    self.ecidFilter = ecidFilter
    super.init(logger: logger)
  }

  // MARK: - Notifications

  fileprivate func handleNotification(device: AMRestorableDevice, status: AMRestorableDeviceNotificationType) {
    // Unrecognised values fall to `.unknown`, which `targetState(for:)` maps the same way its
    // `default` did. `.DFU` would report a real state the device is not in.
    let deviceState = AMRestorableDeviceState(rawValue: calls.RestorableDeviceGetState(device)) ?? .unknown
    let targetState = FBAMRestorableDevice.targetState(for: deviceState)
    let identifier = String(calls.RestorableDeviceGetECID(device))
    logger.log(
      "\(device) \(notificationTypeDescription(status)) in state \(FBiOSTargetStateStringFromState(targetState).rawValue)")

    if let ecidFilter, identifier != ecidFilter {
      logger.log("Ignoring \(device) as it does not match filter of \(ecidFilter)")
      return
    }

    switch status {
    case .connected:
      let info = Dictionary(uniqueKeysWithValues: info(forRestorableDevice: device).map { ($0.key.rawValue, $0.value) })
      logger.log("Caching restorable device values \(info)")
      deviceConnected(device, identifier: identifier, info: info)
    case .disconnected:
      deviceDisconnected(device, identifier: identifier)
    @unknown default:
      logger.log("Unknown Restorable Notification \(status.rawValue)")
    }
  }

  // MARK: - Abstract Implementation

  public override func startListening() throws {
    // Retained for as long as the registration lasts: the callback bridges this back unretained, so
    // the manager must not be deallocated while MobileDevice can still deliver a notification.
    // Balanced in `stopListening`, and below if the registration itself fails.
    let context = Unmanaged.passRetained(self).toOpaque()
    let registrationID = calls.RestorableDeviceRegisterForNotifications(
      restorableDeviceListenerCallback,
      context,
      0,
      0)
    guard registrationID >= 1 else {
      Unmanaged<FBAMRestorableDeviceManager>.fromOpaque(context).release()
      throw FBAMRestorableDeviceManagerError.registrationFailed(status: registrationID)
    }
    self.registrationID = registrationID
    self.notificationContext = context
  }

  public override func stopListening() throws {
    let registrationID = self.registrationID
    self.registrationID = 0
    guard registrationID >= 1 else {
      throw FBAMRestorableDeviceManagerError.notRegistered
    }

    // The return of AMRestorableDeviceUnregisterForNotifications seems to be some random number.
    // However, giving an invalid registrationID is fine and we still get logging.
    _ = calls.RestorableDeviceUnregisterForNotifications(registrationID)
    // No further notification can be delivered, so the callback's context can be given back.
    if let context = notificationContext {
      notificationContext = nil
      Unmanaged<FBAMRestorableDeviceManager>.fromOpaque(context).release()
    }
  }

  public override func constructPublic(
    _ privateDevice: CFTypeRef,
    identifier: String,
    info: [String: Any]?
  ) -> FBAMRestorableDevice {
    FBAMRestorableDevice(
      calls: calls,
      restorableDevice: privateDevice,
      allValues: info ?? [:],
      work: workQueue,
      asyncQueue: asyncQueue,
      logger: logger.withName(identifier))
  }

  public override class func updatePublicReference(
    _ publicDevice: FBAMRestorableDevice,
    privateDevice: CFTypeRef,
    identifier: String,
    info: [String: Any]?
  ) {
    publicDevice.restorableDevice = privateDevice
    publicDevice.allValues = info ?? [:]
  }

  public override class func extractPrivateReference(_ publicDevice: FBAMRestorableDevice) -> Unmanaged<AnyObject>? {
    Unmanaged.passUnretained(publicDevice.restorableDevice)
  }

  // MARK: - Private

  private func info(forRestorableDevice device: AMRestorableDevice) -> [FBDeviceKey: Any] {
    [
      FBDeviceKey.chipID: Int(calls.RestorableDeviceGetChipID(device)),
      FBDeviceKey.deviceClass: Int(calls.RestorableDeviceGetDeviceClass(device)),
      FBDeviceKey.locationID: Int(calls.RestorableDeviceGetLocationID(device)),
      FBDeviceKey.serialNumber: calls.RestorableDeviceCopySerialNumber(device)?.takeRetainedValue() as String? ?? NSNull(),
      FBDeviceKey.deviceName: calls.RestorableDeviceCopyUserFriendlyName(device)?.takeRetainedValue() as String? ?? NSNull(),
      FBDeviceKey.productType: calls.RestorableDeviceCopyProductString(device)?.takeRetainedValue() as String? ?? NSNull(),
      FBDeviceKey.uniqueChipID: NSNumber(value: calls.RestorableDeviceGetECID(device)),
    ]
  }
}

public enum FBAMRestorableDeviceManagerError: Error, LocalizedError {
  case registrationFailed(status: Int32)
  case notRegistered

  public var errorDescription: String? {
    switch self {
    case let .registrationFailed(status):
      return "AMRestorableDeviceRegisterForNotifications failed with \(status)"
    case .notRegistered:
      return "Cannot unregister from AMRestorableDevice notifications, no subscription"
    }
  }
}

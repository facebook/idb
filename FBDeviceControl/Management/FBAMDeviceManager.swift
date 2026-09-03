/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

private let mobileBackupDomain = "com.apple.mobile.backup"
private let serviceReuseTimeout: TimeInterval = 6.0

/// Brings a newly-seen device far enough up to read its values, then registers it.
///
/// Pairing is allowed to fail: an unpaired device still yields the default domain, so it is
/// reported with degraded information rather than dropped.
private func amDeviceConnected(_ device: AMDevice, manager: FBAMDeviceManager) {
  let logger = manager.logger
  let calls = manager.calls

  do {
    // Start with a basic connection. This should always succeed, even if the device is not paired.
    try FBAMDeviceUsage.startConnection(to: device, calls: calls, logger: logger)
  } catch {
    logger.error().log("Cannot connect to device, ignoring device \(error)")
    return
  }

  // The predecessor sent `-stringValue` to whatever `CopyValue` returned, which answers for both
  // a number and a string; accepting only a number would silently drop a device reporting the
  // latter.
  // Erased to `AnyObject` because the call table under-declares `CopyValue` as returning
  // `CFStringRef` while MobileDevice returns whatever CF type the key holds — the predecessor saw
  // it as `id` and let the runtime decide.
  let rawChipID = calls.CopyValue(device, nil, FBDeviceKey.uniqueChipID.rawValue as CFString)?.takeRetainedValue() as AnyObject?
  guard let uniqueChipID = (rawChipID as? NSNumber)?.stringValue ?? (rawChipID as? String) else {
    try? FBAMDeviceUsage.stopConnection(to: device, calls: calls, logger: logger)
    logger.error().log("Ignoring device as cannot obtain ECID for it")
    return
  }

  if let ecidFilter = manager.ecidFilter, uniqueChipID != ecidFilter {
    try? FBAMDeviceUsage.stopConnection(to: device, calls: calls, logger: logger)
    logger.error().log("Ignoring device as ECID \(uniqueChipID) does not match filter \(ecidFilter)")
    return
  }

  var pairedWithSession = true
  do {
    try FBAMDeviceUsage.startSessionByPairing(with: device, calls: calls, logger: logger)
  } catch {
    pairedWithSession = false
    logger.log("Device is not paired, degraded device information will be provied \(error)")
  }

  // Now extract all of the values.
  let info = FBAMDeviceUsage.obtainDeviceValues(device, calls: calls)

  // Stop the session if one was created.
  if pairedWithSession {
    try? FBAMDeviceUsage.stopSession(with: device, calls: calls, logger: logger)
  }
  // Always disconnect, regardless of whether there was a session or not.
  try? FBAMDeviceUsage.stopConnection(to: device, calls: calls, logger: logger)

  guard let info else {
    logger.error().log("Ignoring device as no values were returned for it")
    return
  }
  guard info[FBDeviceKey.uniqueDeviceID.rawValue] != nil else {
    logger.error().log("Ignoring device as \(FBDeviceKey.uniqueDeviceID.rawValue) is not present in \(info)")
    return
  }
  logger.debug().log("Obtained Device Values \(info)")
  manager.deviceConnected(device, identifier: uniqueChipID, info: info)
}

/// The C callback MobileDevice delivers device notifications to.
///
/// A C function cannot capture, so the manager travels as the context pointer registered with the
/// subscription and is bridged back unretained; the subscription holds the only retain.
private func amDeviceListenerCallback(
  _ notification: UnsafeMutablePointer<AMDeviceNotification>?,
  _ context: UnsafeMutableRawPointer?
) {
  guard let notification, let context else {
    return
  }
  let manager = Unmanaged<FBAMDeviceManager>.fromOpaque(context).takeUnretainedValue()
  let logger = manager.logger
  // The struct field is an unaudited CF pointer, so it arrives unmanaged.
  let device = notification.pointee.amDevice.takeUnretainedValue()

  switch notification.pointee.status {
  case .connected, .paired:
    amDeviceConnected(device, manager: manager)
  case .disconnected:
    guard let identifier = manager.identifier(forDevice: device) else {
      logger.log("Cannot obtain identifier for device \(device)")
      return
    }
    manager.deviceDisconnected(device, identifier: identifier)
  case .unsubscribed:
    logger.log("Unsubscribed from AMDeviceNotificationSubscribe")
  default:
    logger.log("Got Unknown status \(notification.pointee.status.rawValue) from AMDeviceNotificationSubscribe")
  }
}

/// Obtains `FBAMDevice` instances.
///
/// Not `@objc`: nothing in Objective-C constructs or names it, and a Swift subclass of a generic
/// Objective-C class cannot be expressed in the generated header.
public final class FBAMDeviceManager: FBDeviceManager<FBAMDevice> {

  // MARK: - Properties

  internal let calls: AMDCalls
  internal let ecidFilter: String?
  private let workQueue: DispatchQueue
  private let asyncQueue: DispatchQueue
  private var subscription: AMDNotificationSubscription?

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

  // MARK: - FBDeviceManager Implementation

  public override func startListening() throws {
    guard subscription == nil else {
      throw FBAMDeviceManagerError.alreadySubscribed
    }

    // Retained for as long as the subscription lasts, so the callback's context stays valid.
    // Tidied up when unsubscribing.
    let context = Unmanaged.passRetained(self).toOpaque()
    var subscription: AMDNotificationSubscription?
    let result = calls.NotificationSubscribe(
      amDeviceListenerCallback,
      0,
      0,
      context,
      &subscription)
    guard result == 0 else {
      Unmanaged<FBAMDeviceManager>.fromOpaque(context).release()
      throw FBAMDeviceManagerError.subscribeFailed(status: result)
    }

    self.subscription = subscription
  }

  public override func stopListening() throws {
    guard let subscription else {
      throw FBAMDeviceManagerError.notSubscribed
    }

    let result = calls.NotificationUnsubscribe(subscription)
    guard result == 0 else {
      throw FBAMDeviceManagerError.unsubscribeFailed(status: result)
    }

    // Cleanup after the subscription.
    Unmanaged.passUnretained(self).release()
    self.subscription = nil
  }

  public override func constructPublic(
    _ privateDevice: CFTypeRef,
    identifier: String,
    info: [String: Any]?
  ) -> FBAMDevice {
    FBAMDevice(
      allValues: info ?? [:],
      calls: calls,
      connectionReuseTimeout: nil,
      serviceReuseTimeout: NSNumber(value: serviceReuseTimeout),
      work: workQueue,
      asyncQueue: asyncQueue,
      logger: logger)
  }

  public override class func updatePublicReference(
    _ publicDevice: FBAMDevice,
    privateDevice: CFTypeRef,
    identifier: String,
    info: [String: Any]?
  ) {
    publicDevice.amDeviceRef = privateDevice
    publicDevice.allValues = info ?? [:]
  }

  public override class func extractPrivateReference(_ publicDevice: FBAMDevice) -> Unmanaged<AnyObject>? {
    guard let reference = publicDevice.amDeviceRef else {
      return nil
    }
    return Unmanaged.passUnretained(reference as AnyObject)
  }

  // MARK: - Private

  fileprivate func identifier(forDevice amDevice: AMDevice) -> String? {
    // Compared by address, as the predecessor did, and the same way `FBDeviceManager` does it —
    // rather than leaving the result to how the opaque reference happens to bridge.
    let address = Unmanaged.passUnretained(amDevice as AnyObject).toOpaque()
    for device in storage.referenced.values {
      if let reference = device.amDeviceRef, Unmanaged.passUnretained(reference as AnyObject).toOpaque() == address {
        return device.uniqueIdentifier
      }
    }
    return nil
  }

}

public enum FBAMDeviceManagerError: Error, LocalizedError {
  case alreadySubscribed
  case notSubscribed
  case subscribeFailed(status: Int32)
  case unsubscribeFailed(status: Int32)
  case connectFailed(device: String, message: String)
  case notPaired(device: String, message: String)
  case pairingValidationFailed(device: String, message: String)
  case sessionFailed(message: String)

  public var errorDescription: String? {
    switch self {
    case .alreadySubscribed:
      return "An AMDeviceNotification Subscription already exists"
    case .notSubscribed:
      return "An AMDeviceNotification Subscription does not exist"
    case let .subscribeFailed(status):
      return "AMDeviceNotificationSubscribe failed with \(status)"
    case let .unsubscribeFailed(status):
      return "AMDeviceNotificationUnsubscribe failed with \(status)"
    case let .connectFailed(device, message):
      return "Failed to connect to \(device). (\(message))"
    case let .notPaired(device, message):
      return "\(device) is not paired with this host \(message)"
    case let .pairingValidationFailed(device, message):
      return "Failed to validate pairing for \(device). (\(message))"
    case let .sessionFailed(message):
      return "Failed to start session with device. (\(message))"
    }
  }
}

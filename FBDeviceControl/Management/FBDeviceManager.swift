/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

/// Discovery of a set of devices, shared by the AMDevice and restorable device sources.
///
/// Subclasses supply how to listen and how to turn a private device reference into a public one;
/// this class owns the registry of what is currently attached and notifies the delegate.
public class FBDeviceManager<PublicDevice: AnyObject>: NSObject, FBiOSTargetSet {

  // MARK: - Properties

  public let logger: any FBControlCoreLogger
  public let storage: FBDeviceStorage<PublicDevice>
  public weak var delegate: (any FBiOSTargetSetDelegate)?

  // MARK: - Initializers

  public init(logger: any FBControlCoreLogger) {
    self.logger = logger
    self.storage = FBDeviceStorage(logger: logger)
    super.init()
  }

  deinit {
    try? stopListening()
  }

  // MARK: - Implemented in Subclasses

  /// Starts listening for device notifications.
  public func startListening() throws {
    throw FBDeviceManagerError.abstractMethod(name: "startListening")
  }

  /// Stops listening for device notifications.
  public func stopListening() throws {
    throw FBDeviceManagerError.abstractMethod(name: "stopListening")
  }

  /// Constructs the public type from the private one.
  public func constructPublic(_ privateDevice: CFTypeRef, identifier: String, info: [String: Any]?) -> PublicDevice {
    fatalError("constructPublic is abstract and must be overridden")
  }

  /// Updates the public type with data from the private one.
  public class func updatePublicReference(
    _ publicDevice: PublicDevice,
    privateDevice: CFTypeRef,
    identifier: String,
    info: [String: Any]?
  ) {
    fatalError("updatePublicReference is abstract and must be overridden")
  }

  /// Extracts the private type from the public one.
  public class func extractPrivateReference(_ publicDevice: PublicDevice) -> Unmanaged<AnyObject>? {
    fatalError("extractPrivateReference is abstract and must be overridden")
  }

  // MARK: - Called in Subclasses

  public func deviceConnected(_ privateDevice: CFTypeRef, identifier: String, info: [String: Any]?) {
    let privateAddress = Unmanaged.passUnretained(privateDevice as AnyObject).toOpaque()
    logger.log("Device Connected \(identifier) (\(privateAddress))")

    // Pull from all known instances created by this class rather than the attached ones: consumers
    // may be holding a device that has been re-connected, and re-using the referenced instance
    // means the underlying reference is replaced beneath them. A device that is no longer
    // referenced has already left the mapping, whose values are weakly held.
    let device: PublicDevice
    if let existing = storage.device(forKey: identifier) {
      logger.info().log("Device has been re-attached \(existing)")
      device = existing
    } else {
      device = constructPublic(privateDevice, identifier: identifier, info: info)
      logger.info().log("Created a new Device instance \(device)")
    }

    // See whether the private reference replaces something already known about.
    let oldPrivateDevice = Self.extractPrivateReference(device)
    if let oldPrivateDevice {
      if oldPrivateDevice.toOpaque() != privateAddress {
        logger.log("New '\(identifier)' (\(privateAddress)) replaces Old Device (\(oldPrivateDevice.toOpaque()))")
        Self.updatePublicReference(device, privateDevice: privateDevice, identifier: identifier, info: info)
      } else {
        logger.log("Existing Device '\(identifier)' (\(privateAddress)) is the same as the old")
      }
    } else {
      logger.log("New '\(identifier)' (\(privateAddress)) appeared for the first time")
      Self.updatePublicReference(device, privateDevice: privateDevice, identifier: identifier, info: info)
    }

    // Update the internal state.
    storage.deviceAttached(device, forKey: identifier)

    // Notify the delegate.
    if let info = device as? any FBiOSTargetInfo {
      delegate?.targetAdded(info, in: self)
    }
  }

  public func deviceDisconnected(_ privateDevice: CFTypeRef, identifier: String) {
    // The private ref may already be dead by the time a disconnect callback fires, so log it by
    // identifier and address only; never dereference it.
    let privateAddress = Unmanaged.passUnretained(privateDevice as AnyObject).toOpaque()
    logger.log("Device Disconnected \(identifier) (\(privateAddress))")
    guard let device = storage.device(forKey: identifier) else {
      logger.log("No Device named \(identifier) from attached devices, nothing to remove")
      return
    }
    logger.log("Removing Device \(identifier) from attached devices")

    // Update the internal state.
    storage.deviceDetached(forKey: identifier)

    // Notify the delegate.
    if let info = device as? any FBiOSTargetInfo {
      delegate?.targetRemoved(info, in: self)
    }
  }

  // MARK: - Public

  public var currentDeviceList: [PublicDevice] {
    Array(storage.attached.values).sorted { lhs, rhs in
      let lhsID = (lhs as? any FBiOSTargetInfo)?.uniqueIdentifier ?? ""
      let rhsID = (rhs as? any FBiOSTargetInfo)?.uniqueIdentifier ?? ""
      return lhsID < rhsID
    }
  }

  // MARK: - FBiOSTargetSet

  public var allTargetInfos: [any FBiOSTargetInfo] {
    currentDeviceList.compactMap { $0 as? any FBiOSTargetInfo }
  }

  public func target(withUDID udid: String) -> (any FBiOSTargetInfo)? {
    allTargetInfos.first { FBiOSTargetPredicateForUDID(udid).evaluate(with: $0) }
  }

  // MARK: - NSObject

  public override var description: String {
    "\(type(of: self)): \(FBCollectionInformation.oneLineDescription(from: allTargetInfos))"
  }
}

public enum FBDeviceManagerError: Error, LocalizedError {
  case abstractMethod(name: String)

  public var errorDescription: String? {
    switch self {
    case let .abstractMethod(name):
      return "\(name) is abstract and must be overridden"
    }
  }
}

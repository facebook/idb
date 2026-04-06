// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

@preconcurrency import FBControlCore
import Foundation

@objc(FBDeviceStorage)
public class _FBDeviceStorageBase: NSObject {

  @objc public var attached: [String: Any] {
    attachedDevices
  }

  @objc public var referenced: [String: Any] {
    var result: [String: Any] = [:]
    let enumerator = referencedDevices.keyEnumerator()
    while let key = enumerator.nextObject() as? NSString {
      if let value = referencedDevices.object(forKey: key) {
        result[key as String] = value
      }
    }
    return result
  }

  private let logger: any FBControlCoreLogger
  private var attachedDevices: [String: Any]
  private var referencedDevices: NSMapTable<NSString, AnyObject>

  @objc public init(logger: any FBControlCoreLogger) {
    self.logger = logger
    self.attachedDevices = [:]
    self.referencedDevices = NSMapTable(keyOptions: .copyIn, valueOptions: .weakMemory)
    super.init()
  }

  @objc public func deviceAttached(_ device: Any, forKey key: String) {
    let attached = attachedDevices[key]
    let referenced = referencedDevices.object(forKey: key as NSString)
    if attached != nil && referenced != nil {
      logger.log("\(device) is an attached device update")
    } else if referenced != nil {
      logger.log("\(device) is referenced and now attached again")
    } else {
      logger.log("\(device) appeared for the first time")
    }
    attachedDevices[key] = device
    referencedDevices.setObject(device as AnyObject, forKey: key as NSString)
  }

  @objc public func deviceDetached(forKey key: String) {
    attachedDevices.removeValue(forKey: key)
  }

  @objc public func device(forKey key: String) -> Any? {
    attachedDevices[key] ?? referencedDevices.object(forKey: key as NSString)
  }
}

/// Generic wrapper for Swift consumers. The generic parameter is erased at runtime.
/// ObjC code sees `FBDeviceStorage` (the @objc name of _FBDeviceStorageBase).
public class FBDeviceStorage<T: AnyObject>: _FBDeviceStorageBase {
}

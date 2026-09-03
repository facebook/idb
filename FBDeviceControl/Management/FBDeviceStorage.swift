/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

/// Holds both the currently-attached devices and weak references to every device this storage has
/// ever vended, so a consumer holding a device across a disconnect gets the same instance back on
/// re-attach.
public final class FBDeviceStorage<T: AnyObject> {

  public var attached: [String: T] {
    attachedDevices
  }

  public var referenced: [String: T] {
    var result: [String: T] = [:]
    let enumerator = referencedDevices.keyEnumerator()
    while let key = enumerator.nextObject() as? NSString {
      if let value = referencedDevices.object(forKey: key) as? T {
        result[key as String] = value
      }
    }
    return result
  }

  private let logger: any FBControlCoreLogger
  private var attachedDevices: [String: T]
  private var referencedDevices: NSMapTable<NSString, AnyObject>

  public init(logger: any FBControlCoreLogger) {
    self.logger = logger
    self.attachedDevices = [:]
    self.referencedDevices = NSMapTable(keyOptions: .copyIn, valueOptions: .weakMemory)
  }

  public func deviceAttached(_ device: T, forKey key: String) {
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
    referencedDevices.setObject(device, forKey: key as NSString)
  }

  public func deviceDetached(forKey key: String) {
    attachedDevices.removeValue(forKey: key)
  }

  public func device(forKey key: String) -> T? {
    attachedDevices[key] ?? referencedDevices.object(forKey: key as NSString) as? T
  }
}

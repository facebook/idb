/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
import FBControlCore
@testable import FBSimulatorControl
import Foundation

// Every member of these doubles is messaged through the Objective-C runtime: each is
// substituted for the CoreSimulator class of the same shape and reached either from
// `FBSimulator.m` or from Swift through an `unsafeBitCast`. `@objc` is spelled out per
// member rather than applied wholesale to the class, so a member that stops being
// representable in Objective-C fails to compile instead of silently vanishing from the
// class at runtime.

class SimulatorControlTests_SimDeviceType_Double: NSObject {
  @objc var name: String = ""
}

class SimulatorControlTests_SimDeviceRuntime_Double: NSObject {
  @objc var name: String = ""
  @objc var versionString: String = ""
  @objc var buildVersionString: String = ""
  @objc var available: Bool = true
  @objc var supportedProductFamilyIDs: [NSNumber] = []
}

class SimulatorControlTests_SimDevice_Double: NSObject {
  @objc var name: String = ""
  @objc var UDID: NSUUID = NSUUID()
  private var _dataPath: String?
  @objc var dataPath: String {
    get {
      if _dataPath == nil {
        let path = (NSTemporaryDirectory() as NSString)
          .appendingPathComponent("SimDevice_Double")
          .appendingFormat("/%@_Data", UDID.uuidString)
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        _dataPath = path
      }
      return _dataPath!
    }
    set {
      _dataPath = newValue
    }
  }
  @objc var state: UInt64 = 0
  @objc var deviceType: SimulatorControlTests_SimDeviceType_Double?
  @objc var runtime: SimulatorControlTests_SimDeviceRuntime_Double?
  @objc var notificationManager: AnyObject?

  override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? SimulatorControlTests_SimDevice_Double else { return false }
    return UDID.isEqual(other.UDID)
  }

  /// Mirrors the real `SimDevice`, which vends this as a string to the Objective-C runtime.
  @objc var stateString: String {
    // A state the enum does not name reads as unknown, rather than trapping the whole suite.
    return (FBiOSTargetState(rawValue: UInt(state)) ?? .unknown).stateString.rawValue
  }
}

class SimulatorControlTests_SimDeviceSet_Double: NSObject {
  @objc var availableDevices: [Any] = []
  @objc var notificationManager: AnyObject?
}

/// Stands in for the object vended by `SimDevice.notificationManager`, letting a test drive the
/// registered handler directly and observe that it is unregistered.
///
/// `@unchecked Sendable`: all mutable state is guarded by `lock`.
final class SimulatorControlTests_SimDeviceNotifier_Double: NSObject, SimDeviceNotifier, @unchecked Sendable {
  private let lock = NSLock()
  private var nextHandle: UInt64 = 1
  private var handlers: [UInt64: (queue: DispatchQueue, handler: ([AnyHashable: Any]?) -> Void)] = [:]
  private var unregistered: [UInt64] = []

  var registeredHandleCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return handlers.count
  }

  var unregisteredHandles: [UInt64] {
    lock.lock()
    defer { lock.unlock() }
    return unregistered
  }

  /// Delivers `info` to every registered handler, synchronously on the queue it registered with.
  func post(_ info: [String: Any]) {
    lock.lock()
    let targets = Array(handlers.values)
    lock.unlock()
    for target in targets {
      target.queue.sync {
        target.handler(info)
      }
    }
  }

  func registerNotificationHandler(on queue: DispatchQueue?, handler: (([AnyHashable: Any]?) -> Void)?) -> UInt64 {
    guard let queue, let handler else {
      return 0
    }
    lock.lock()
    defer { lock.unlock() }
    let handle = nextHandle
    nextHandle += 1
    handlers[handle] = (queue: queue, handler: handler)
    return handle
  }

  func unregisterNotificationHandler(_ handle: UInt64, error: AutoreleasingUnsafeMutablePointer<AnyObject?>?) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    unregistered.append(handle)
    return handlers.removeValue(forKey: handle) != nil
  }
}

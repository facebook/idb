/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import Foundation

// Every member of these doubles is messaged through the Objective-C runtime: each is
// substituted for the CoreSimulator class of the same shape and reached either from
// `FBSimulator.m` or from Swift through an `unsafeBitCast`. `@objc` is spelled out per
// member rather than applied wholesale to the class, so a member that stops being
// representable in Objective-C fails to compile instead of silently vanishing from the
// class at runtime.

class FBSimulatorControlTests_SimDeviceType_Double: NSObject {
  @objc var name: String = ""
}

class FBSimulatorControlTests_SimDeviceRuntime_Double: NSObject {
  @objc var name: String = ""
  @objc var versionString: String = ""
}

class FBSimulatorControlTests_SimDevice_Double: NSObject {
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
  @objc var deviceType: FBSimulatorControlTests_SimDeviceType_Double?
  @objc var runtime: FBSimulatorControlTests_SimDeviceRuntime_Double?
  @objc var notificationManager: AnyObject?

  override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? FBSimulatorControlTests_SimDevice_Double else { return false }
    return UDID.isEqual(other.UDID)
  }

  /// Mirrors the real `SimDevice`, which vends this as a string to the Objective-C runtime.
  @objc var stateString: String {
    // A state the enum does not name reads as unknown, rather than trapping the whole suite.
    return FBiOSTargetStateStringFromState(FBiOSTargetState(rawValue: UInt(state)) ?? .unknown).rawValue
  }
}

class FBSimulatorControlTests_SimDeviceSet_Double: NSObject {
  @objc var availableDevices: [Any] = []
  @objc var notificationManager: AnyObject?
}

/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Foundation

@objcMembers
class FBSimulatorControlTests_SimDeviceType_Double: NSObject {
  var name: String = ""
}

@objcMembers
class FBSimulatorControlTests_SimDeviceRuntime_Double: NSObject {
  var name: String = ""
  var versionString: String = ""
}

@objcMembers
class FBSimulatorControlTests_SimDevice_Double: NSObject {
  var name: String = ""
  var UDID: NSUUID = NSUUID()
  private var _dataPath: String?
  var dataPath: String {
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
  var state: UInt64 = 0
  var deviceType: FBSimulatorControlTests_SimDeviceType_Double?
  var runtime: FBSimulatorControlTests_SimDeviceRuntime_Double?
  var notificationManager: AnyObject?

  override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? FBSimulatorControlTests_SimDevice_Double else { return false }
    return UDID.isEqual(other.UDID)
  }

  var stateString: FBiOSTargetStateString {
    return FBiOSTargetStateStringFromState(FBiOSTargetState(rawValue: UInt(state))!)
  }
}

@objcMembers
class FBSimulatorControlTests_SimDeviceSet_Double: NSObject {
  var availableDevices: [Any] = []
  var notificationManager: AnyObject?
}

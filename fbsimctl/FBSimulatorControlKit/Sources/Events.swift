/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import Foundation
import FBControlCore
import FBSimulatorControl

public typealias EventName = FBEventName

extension EventName {
  static let boot = EventName(rawValue: FBiOSTargetActionType.boot.rawValue)
  static let hid = EventName(rawValue: FBiOSTargetActionType.HID.rawValue)
  static let approve = EventName(rawValue: FBiOSTargetActionType.approval.rawValue)
  static let accessibilityFetch = EventName(rawValue: FBiOSTargetActionType.acessibilityFetch.rawValue)
  static let logTail = EventName(rawValue: FBiOSTargetActionType.logTail.rawValue)
}

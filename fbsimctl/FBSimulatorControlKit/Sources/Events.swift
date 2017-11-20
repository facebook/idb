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
  static let boot = EventName(rawValue: FBiOSTargetFutureType.boot.rawValue)
  static let hid = EventName(rawValue: FBiOSTargetFutureType.HID.rawValue)
  static let approve = EventName(rawValue: FBiOSTargetFutureType.approval.rawValue)
  static let accessibilityFetch = EventName(rawValue: FBiOSTargetFutureType.acessibilityFetch.rawValue)
  static let logTail = EventName(rawValue: FBiOSTargetFutureType.logTail.rawValue)
}

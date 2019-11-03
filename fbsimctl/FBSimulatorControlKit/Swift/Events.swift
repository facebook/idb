/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import FBSimulatorControl
import Foundation

public typealias EventName = FBEventName

extension EventName {
  static let contactsUpdate = EventName(rawValue: FBiOSTargetFutureType.contactsUpdate.rawValue)
  static let boot = EventName(rawValue: FBiOSTargetFutureType.boot.rawValue)
  static let hid = EventName(rawValue: FBiOSTargetFutureType.HID.rawValue)
  static let approve = EventName(rawValue: FBiOSTargetFutureType.approval.rawValue)
  static let accessibilityFetch = EventName(rawValue: FBiOSTargetFutureType.accessibilityFetch.rawValue)
  static let logTail = EventName(rawValue: FBiOSTargetFutureType.logTail.rawValue)
}

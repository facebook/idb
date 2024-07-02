/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

class IDBConfiguration: NSObject {

  @objc static var eventReporter: FBEventReporter = EmptyEventReporter.shared
  @objc static var swiftEventReporter: FBEventReporter = EmptyEventReporter.shared

  static var idbKillswitch: IDBKillswitch = EmptyIDBKillswitch()

  @objc static func getIDBKillswitch() -> IDBKillswitchBridge {
    return idbKillswitch.objcBridged
  }
}

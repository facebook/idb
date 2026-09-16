/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import XCTest

final class NotificationExceptionTests: XCTestCase {
  func testPrivateExceptionsAtCommandBoundary() {
    for operation in [
      "lookup", "write", "list", "allowsNotifications", "authorizationStatus",
      "setAllowsNotifications", "setAuthorizationStatus", "setAlertType", "setLockScreenSetting", "setNotificationCenterSetting",
    ] {
      XCTAssertEqual(FBNotificationCommandExceptionResult(operation) as NSDictionary, ["status": 1] as NSDictionary)
    }
  }
}

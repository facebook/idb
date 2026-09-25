/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
@_implementationOnly import SimulatorFrameworkBridgeSupport
import XCTest

final class ContactsServiceTests: XCTestCase {

  func testUnknownActionReturnsFailure() {
    XCTAssertEqual(FBContactsService.handleContactsAction(action: "delete"), 1)
    XCTAssertEqual(FBContactsService.handleContactsAction(action: ""), 1)
    XCTAssertEqual(FBContactsService.handleContactsAction(action: "add"), 1)
  }
}

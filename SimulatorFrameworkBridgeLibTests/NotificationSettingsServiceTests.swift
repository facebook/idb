/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
import Foundation
@_implementationOnly import SimulatorFrameworkBridgeLib
import XCTest

final class NotificationSettingsServiceTests: XCTestCase {
  var gateway = FakeNotificationSettingsGateway()

  override func setUp() {
    super.setUp()
    XCTAssertNotEqual(
      dlopen("/System/Library/PrivateFrameworks/BulletinBoard.framework/BulletinBoard", RTLD_NOW),
      nil
    )
    gateway = FakeNotificationSettingsGateway()
  }

  func testApproveSetsAuthorizedState() {
    let bundleID = "com.example.test.approve"

    XCTAssertEqual(handleNotificationSettingsActionWithGateway("approve", bundleID, gateway), 0)

    let sectionInfo = gateway.sectionInfo(forSectionID: bundleID)
    XCTAssertNotNil(sectionInfo)
    XCTAssertTrue(FBNotificationAllowsNotifications(sectionInfo))
    XCTAssertEqual(FBNotificationAuthorizationStatus(sectionInfo), 2)
  }

  func testRevokeResetsExistingSection() {
    let bundleID = "com.example.test.revoke"
    XCTAssertEqual(handleNotificationSettingsActionWithGateway("approve", bundleID, gateway), 0)

    XCTAssertEqual(handleNotificationSettingsActionWithGateway("revoke", bundleID, gateway), 0)

    let sectionInfo = gateway.sectionInfo(forSectionID: bundleID)
    XCTAssertNotNil(sectionInfo)
    XCTAssertFalse(FBNotificationAllowsNotifications(sectionInfo))
    XCTAssertEqual(FBNotificationAuthorizationStatus(sectionInfo), 0)
  }

  func testRevokeWithoutAnExistingSectionSucceeds() {
    let bundleID = "com.example.test." + UUID().uuidString

    XCTAssertEqual(handleNotificationSettingsActionWithGateway("revoke", bundleID, gateway), 0)
    XCTAssertNil(gateway.sectionInfo(forSectionID: bundleID))
  }

  func testRevokeWithoutABundleIDReturnsFailure() {
    XCTAssertEqual(handleNotificationSettingsActionWithGateway("revoke", nil, gateway), 1)
  }

  func testCheckSucceeds() {
    XCTAssertEqual(handleNotificationSettingsActionWithGateway("check", "com.example.test", gateway), 0)
  }

  func testListWithoutABundleIDSucceeds() {
    XCTAssertEqual(handleNotificationSettingsActionWithGateway("list", nil, gateway), 0)
  }

  func testUnknownActionReturnsFailure() {
    XCTAssertEqual(
      handleNotificationSettingsActionWithGateway("unknown", "com.example.test", gateway),
      1
    )
  }
}

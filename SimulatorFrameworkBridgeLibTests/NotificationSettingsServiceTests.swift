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

  func testApproveMakesNotificationsRetainable() {
    // The effective flags, as distinct from the user-preference settings above.
    // BulletinBoard honours these when deciding whether to keep a delivered notification, so
    // approving without them leaves an app that shows a banner and retains nothing.
    let bundleID = "com.example.test.retention"

    XCTAssertEqual(handleNotificationSettingsActionWithGateway("approve", bundleID, gateway), 0)

    let sectionInfo = gateway.sectionInfo(forSectionID: bundleID)
    XCTAssertTrue(FBNotificationShowsInNotificationCenter(sectionInfo))
    XCTAssertTrue(FBNotificationShowsInLockScreen(sectionInfo))
  }

  func testRevokeLeavesTheEffectiveFlagsForTheNextGrantToOwn() {
    // Measured on iOS 26.2: a system grant writes the authorization but not these flags, so a
    // revoke that cleared them would outlive itself -- the app comes back authorized from the
    // normal prompt with retention still off, which is the state this service exists to
    // prevent. Revoke resets the authorization; what a re-granted app retains is the grant's
    // to decide.
    let bundleID = "com.example.test.retention.revoke"
    XCTAssertEqual(handleNotificationSettingsActionWithGateway("approve", bundleID, gateway), 0)

    XCTAssertEqual(handleNotificationSettingsActionWithGateway("revoke", bundleID, gateway), 0)

    let sectionInfo = gateway.sectionInfo(forSectionID: bundleID)
    XCTAssertFalse(FBNotificationAllowsNotifications(sectionInfo))
    XCTAssertEqual(FBNotificationAuthorizationStatus(sectionInfo), 0)
    XCTAssertTrue(FBNotificationShowsInNotificationCenter(sectionInfo))
    XCTAssertTrue(FBNotificationShowsInLockScreen(sectionInfo))
  }

  func testApproveStillAuthorizesWhenTheRuntimeHasNoEffectiveFlags() {
    // Whether the flags exist is a property of the runtime, not of the request. Refusing here
    // would take away the authorization approve used to grant on such a runtime, rather than
    // adding the retention it cannot; the app is authorized and `check` reports the flags as
    // unknown.
    let bundleID = "com.example.test.retention.absent"
    let section = FBSectionInfoWithoutEffectiveFlags()
    gateway.setSectionInfo(section, forSectionID: bundleID)

    XCTAssertEqual(handleNotificationSettingsActionWithGateway("approve", bundleID, gateway), 0)

    XCTAssertTrue(section.allowsNotifications)
    XCTAssertEqual(section.authorizationStatus, 2)
    XCTAssertEqual(section.alertType, 1)
    XCTAssertEqual(section.lockScreenSetting, 1)
    XCTAssertEqual(section.notificationCenterSetting, 1)
  }

  func testApproveWritesTheEffectiveFlagThisRuntimeHas() {
    // The two flags are independent capabilities. Probing them together would write neither on
    // a runtime carrying one, turning off the retention this can configure there -- and `check`
    // reads them separately, so it would then report `false` for a flag approve never wrote.
    let bundleID = "com.example.test.retention.partial"
    let section = FBSectionInfoWithOnlyNotificationCenterFlag()
    gateway.setSectionInfo(section, forSectionID: bundleID)

    XCTAssertEqual(handleNotificationSettingsActionWithGateway("approve", bundleID, gateway), 0)

    XCTAssertTrue(section.showsInNotificationCenter)
    XCTAssertTrue(section.allowsNotifications)
    XCTAssertEqual(section.authorizationStatus, 2)
  }

  func testCheckAgreesWithApproveOnARuntimeCarryingOneFlag() {
    // The read and the write have to classify the same runtime the same way: the flag that
    // exists reads back as the `true` approve wrote, and the absent one as `null` rather than
    // as a `false` that would say the app is configured to retain nothing.
    let bundleID = "com.example.test.retention.partial.check"
    gateway.setSectionInfo(FBSectionInfoWithOnlyNotificationCenterFlag(), forSectionID: bundleID)
    XCTAssertEqual(handleNotificationSettingsActionWithGateway("approve", bundleID, gateway), 0)
    var result: Int32 = -1

    let output = FBStdoutWhileRunning {
      result = handleNotificationSettingsActionWithGateway("check", bundleID, self.gateway)
    }

    XCTAssertEqual(result, 0)
    let printed = FBParsedJSONLine(output)
    XCTAssertEqual(printed?["showsInNotificationCenter"] as? Bool, true)
    XCTAssertTrue(printed?["showsInLockScreen"] is NSNull)
  }

  func testStdoutCaptureOutlivesAPipeBufferOfOutput() {
    // The capture drains while the block runs. Draining only afterwards deadlocks the whole
    // test process once a block prints more than a pipe holds, which the services this helper
    // is shared with can: a listing prints a record per section.
    let line = String(repeating: "x", count: 1024)
    let expected = 256 // 256 KiB, past any Darwin pipe buffer

    let output = FBStdoutWhileRunning {
      for _ in 0..<expected {
        // `fputs` rather than `print`: the capture exists to read what the services write to
        // stdout, and they write with `printf`. A logger would not reach the pipe under test.
        fputs(line + "\n", stdout)
      }
    }

    XCTAssertEqual(output.count, expected * (line.count + 1))
  }

  func testRevokeSucceedsWhenTheRuntimeHasNoEffectiveFlags() {
    let bundleID = "com.example.test.retention.absent.revoke"
    let section = FBSectionInfoWithoutEffectiveFlags()
    section.allowsNotifications = true
    section.authorizationStatus = 2
    gateway.setSectionInfo(section, forSectionID: bundleID)

    XCTAssertEqual(handleNotificationSettingsActionWithGateway("revoke", bundleID, gateway), 0)

    XCTAssertFalse(section.allowsNotifications)
    XCTAssertEqual(section.authorizationStatus, 0)
  }

  func testCheckReportsTheEffectiveFlagsApproveWrote() {
    // Approve writes the two together, so a check that reported one of them could not say
    // whether the app will retain what it is shown.
    let bundleID = "com.example.test.retention.check"
    XCTAssertEqual(handleNotificationSettingsActionWithGateway("approve", bundleID, gateway), 0)
    var result: Int32 = -1

    let output = FBStdoutWhileRunning {
      result = handleNotificationSettingsActionWithGateway("check", bundleID, self.gateway)
    }

    XCTAssertEqual(result, 0)
    let printed = FBParsedJSONLine(output)
    XCTAssertEqual(printed?["showsInNotificationCenter"] as? Bool, true)
    XCTAssertEqual(printed?["showsInLockScreen"] as? Bool, true)
  }

  func testCheckReadsASectionWithoutTheEffectiveFlags() {
    // Reading either flag unconditionally would raise rather than report it as unknown, and
    // `false` would say the app is configured to retain nothing rather than that this runtime
    // cannot answer.
    let bundleID = "com.example.test.retention.absent.check"
    gateway.setSectionInfo(FBSectionInfoWithoutEffectiveFlags(), forSectionID: bundleID)
    var result: Int32 = -1

    let output = FBStdoutWhileRunning {
      result = handleNotificationSettingsActionWithGateway("check", bundleID, self.gateway)
    }

    XCTAssertEqual(result, 0)
    let printed = FBParsedJSONLine(output)
    XCTAssertTrue(printed?["showsInNotificationCenter"] is NSNull)
    XCTAssertTrue(printed?["showsInLockScreen"] is NSNull)
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

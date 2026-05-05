/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import XCTest

// MARK: - Simulator Test Double

private class SimDouble: NSObject {
  let workQueue = DispatchQueue(label: "com.test.settings.work")
  let asyncQueue = DispatchQueue(label: "com.test.settings.async")
  var logger: (any FBControlCoreLogger)?
  var dataDirectory: String?
}

// MARK: - Tests

final class FBSimulatorSettingsCommandsTests: XCTestCase {

  // MARK: - Helpers

  private var simDoubleStrongRef: SimDouble?

  private func makeCommands() -> FBSimulatorSettingsCommands {
    let sim = SimDouble()
    simDoubleStrongRef = sim
    let casted = unsafeBitCast(sim, to: FBSimulator.self)
    return FBSimulatorSettingsCommands(simulator: casted)
  }

  private func assertFuture(_ future: FBFuture<NSNull>, failsWithTimeout timeout: TimeInterval, message: String) {
    XCTAssertThrowsError(try future.`await`(withTimeout: timeout), message)
  }

  // MARK: - Filtered TCC Approvals

  private static let notification = FBTargetSettingsService(rawValue: "notification")
  private static let health = FBTargetSettingsService(rawValue: "health")

  func testFilteredTCCApprovalsKeepsOnlyTCCServices() {
    let input: Set<FBTargetSettingsService> = [
      .contacts, .photos, .location, Self.notification,
    ]
    let filtered = FBSimulatorSettingsCommands.filteredTCCApprovals(input)
    XCTAssertTrue(filtered.contains(.contacts), "Contacts is in TCC mapping and should be kept")
    XCTAssertTrue(filtered.contains(.photos), "Photos is in TCC mapping and should be kept")
    XCTAssertFalse(filtered.contains(.location), "Location is NOT in TCC mapping and should be removed")
    XCTAssertFalse(filtered.contains(Self.notification), "Notification is NOT in TCC mapping and should be removed")
  }

  func testFilteredTCCApprovalsReturnsEmptyForNonTCCServices() {
    let input: Set<FBTargetSettingsService> = [
      .location, Self.notification, Self.health,
    ]
    let filtered = FBSimulatorSettingsCommands.filteredTCCApprovals(input)
    XCTAssertEqual(
      filtered.count, 0,
      "Should return empty set when no input services are in TCC mapping")
  }

  func testFilteredTCCApprovalsKeepsAllFourTCCServices() {
    let input: Set<FBTargetSettingsService> = [
      .contacts, .photos, .camera, .microphone,
    ]
    let filtered = FBSimulatorSettingsCommands.filteredTCCApprovals(input)
    XCTAssertEqual(
      filtered.count, 4,
      "All four TCC-backed services should pass through the filter")
  }

  // MARK: - Magic Deeplink Key

  func testMagicDeeplinkKeyFormatsCorrectly() {
    let key = FBSimulatorSettingsCommands.magicDeeplinkKey(forScheme: "myapp")
    XCTAssertEqual(
      key, "com.apple.CoreSimulator.CoreSimulatorBridge-->myapp",
      "Deeplink key should use CoreSimulatorBridge prefix with --> separator")
  }

  func testMagicDeeplinkKeyHandlesComplexScheme() {
    let key = FBSimulatorSettingsCommands.magicDeeplinkKey(forScheme: "fb-messenger-api")
    XCTAssertEqual(
      key, "com.apple.CoreSimulator.CoreSimulatorBridge-->fb-messenger-api",
      "Deeplink key should handle hyphenated scheme names")
  }

  // MARK: - Approval Row Generation

  func testPreiOS12RowsContainBundleIDAndServiceName() {
    let bundleIDs: Set<String> = ["com.test.app"]
    let services: Set<FBTargetSettingsService> = [.contacts]
    let rows = FBSimulatorSettingsCommands.preiOS12ApprovalRows(forBundleIDs: bundleIDs, services: services)
    XCTAssertTrue(
      rows.contains("kTCCServiceAddressBook"),
      "Row should reference the TCC service name from the mapping")
    XCTAssertTrue(
      rows.contains("com.test.app"),
      "Row should embed the bundle ID")
  }

  func testPostiOS15RowsUseAuthValue2ForAVCaptureCompatibility() {
    let bundleIDs: Set<String> = ["com.test.app"]
    let services: Set<FBTargetSettingsService> = [.camera]
    let rows = FBSimulatorSettingsCommands.postiOS15ApprovalRows(forBundleIDs: bundleIDs, services: services)
    // auth_value=2 is required for AVCaptureDevice.authorizationStatus to return
    // something other than notDetermined
    XCTAssertTrue(
      rows.contains("0, 2, 2, 2"),
      "Post-iOS 15 must use auth_value=2 for AVCaptureDevice compatibility")
  }

  func testPostiOS17RowsIncludePidAndBootUuidColumns() {
    let bundleIDs: Set<String> = ["com.test.app"]
    let services: Set<FBTargetSettingsService> = [.microphone]
    let rows17 = FBSimulatorSettingsCommands.postiOS17ApprovalRows(forBundleIDs: bundleIDs, services: services)
    let rows15 = FBSimulatorSettingsCommands.postiOS15ApprovalRows(forBundleIDs: bundleIDs, services: services)
    XCTAssertGreaterThan(
      rows17.count, rows15.count,
      "iOS 17 rows should be longer than iOS 15 due to additional columns")
    XCTAssertTrue(
      rows17.contains("'UNUSED'"),
      "iOS 17 rows should contain boot_uuid placeholder")
  }

  func testApprovalRowsGenerateCorrectCountForMultipleInputs() {
    let bundleIDs: Set<String> = ["com.app1", "com.app2"]
    let services: Set<FBTargetSettingsService> = [.contacts, .photos]
    let rows = FBSimulatorSettingsCommands.preiOS12ApprovalRows(forBundleIDs: bundleIDs, services: services)
    let tuples = rows.components(separatedBy: "), (")
    XCTAssertEqual(
      tuples.count, 4,
      "Should generate one tuple per bundleID-service combination (2x2=4)")
  }

  func testApprovalRowsFilterToTCCServicesOnly() {
    let bundleIDs: Set<String> = ["com.test.app"]
    let services: Set<FBTargetSettingsService> = [.contacts, .location]
    let rows = FBSimulatorSettingsCommands.preiOS12ApprovalRows(forBundleIDs: bundleIDs, services: services)
    XCTAssertTrue(
      rows.contains("kTCCServiceAddressBook"),
      "Should include contacts which is in TCC mapping")
    XCTAssertFalse(
      rows.contains("location"),
      "Should not include location which is not in TCC mapping")
  }

  // MARK: - Grant/Revoke Access Input Validation

  func testGrantAccessRejectsEmptyServices() {
    let cmds = makeCommands()
    assertFuture(
      cmds.grantAccess(["com.test"], toServices: []),
      failsWithTimeout: 1.0,
      message: "grantAccess should reject empty services set")
  }

  func testGrantAccessRejectsEmptyBundleIDs() {
    let cmds = makeCommands()
    assertFuture(
      cmds.grantAccess([], toServices: [.contacts]),
      failsWithTimeout: 1.0,
      message: "grantAccess should reject empty bundle IDs set")
  }

  func testRevokeAccessRejectsEmptyServices() {
    let cmds = makeCommands()
    assertFuture(
      cmds.revokeAccess(["com.test"], toServices: []),
      failsWithTimeout: 1.0,
      message: "revokeAccess should reject empty services set")
  }

  func testRevokeAccessRejectsEmptyBundleIDs() {
    let cmds = makeCommands()
    assertFuture(
      cmds.revokeAccess([], toServices: [.contacts]),
      failsWithTimeout: 1.0,
      message: "revokeAccess should reject empty bundle IDs set")
  }

  // MARK: - Deeplink Access Validation

  func testGrantDeeplinkRejectsEmptyScheme() {
    let cmds = makeCommands()
    assertFuture(
      cmds.grantAccess(["com.test"], toDeeplink: ""),
      failsWithTimeout: 1.0,
      message: "grantAccess(toDeeplink:) should reject empty scheme")
  }

  func testGrantDeeplinkRejectsEmptyBundleIDs() {
    let cmds = makeCommands()
    assertFuture(
      cmds.grantAccess([], toDeeplink: "myapp"),
      failsWithTimeout: 1.0,
      message: "grantAccess(toDeeplink:) should reject empty bundle IDs")
  }

  func testRevokeDeeplinkRejectsEmptyScheme() {
    let cmds = makeCommands()
    assertFuture(
      cmds.revokeAccess(["com.test"], toDeeplink: ""),
      failsWithTimeout: 1.0,
      message: "revokeAccess(toDeeplink:) should reject empty scheme")
  }

  func testRevokeDeeplinkRejectsEmptyBundleIDs() {
    let cmds = makeCommands()
    assertFuture(
      cmds.revokeAccess([], toDeeplink: "myapp"),
      failsWithTimeout: 1.0,
      message: "revokeAccess(toDeeplink:) should reject empty bundle IDs")
  }

  // MARK: - DNS Validation

  func testSetDnsServersRejectsEmptyArray() {
    let cmds = makeCommands()
    assertFuture(
      cmds.setDnsServers([]),
      failsWithTimeout: 1.0,
      message: "setDnsServers should reject empty array")
  }
}

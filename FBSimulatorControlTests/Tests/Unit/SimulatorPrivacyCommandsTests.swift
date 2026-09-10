/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import XCTest

final class SimulatorPrivacyCommandsTests: XCTestCase {

  // MARK: - Helpers

  private func makeSimulator() -> FBSimulator {
    SimulatorTestSupport.testableSimulator()
  }

  private func assertThrowsAsync(
    _ message: String,
    _ expression: () async throws -> Void,
    expecting isExpected: (SimulatorPrivacyError) -> Bool
  ) async {
    do {
      try await expression()
      XCTFail(message)
    } catch let error as SimulatorPrivacyError where isExpected(error) {
      // Expected.
    } catch {
      XCTFail("\(message); threw \(error)")
    }
  }

  // MARK: - Filtered TCC Approvals

  func testFilteredTCCApprovalsKeepsOnlyTCCServices() {
    let input: Set<FBTargetSettingsService> = [
      .contacts, .photos, .location, .notification,
    ]
    let filtered = SimulatorPrivacyCommands.filteredTCCApprovals(input)
    XCTAssertTrue(filtered.contains(.contacts), "Contacts is in TCC mapping and should be kept")
    XCTAssertTrue(filtered.contains(.photos), "Photos is in TCC mapping and should be kept")
    XCTAssertFalse(filtered.contains(.location), "Location is NOT in TCC mapping and should be removed")
    XCTAssertFalse(filtered.contains(.notification), "Notification is NOT in TCC mapping and should be removed")
  }

  // MARK: - Magic Deeplink Key

  func testMagicDeeplinkKeyFormatsCorrectly() {
    let key = SimulatorPrivacyCommands.magicDeeplinkKey(forScheme: "myapp")
    XCTAssertEqual(
      key, "com.apple.CoreSimulator.CoreSimulatorBridge-->myapp",
      "Deeplink key should use CoreSimulatorBridge prefix with --> separator")
  }

  // MARK: - Approval Row Generation

  func testPreiOS12RowsContainBundleIDAndServiceName() {
    let bundleIDs: Set<String> = ["com.test.app"]
    let services: Set<FBTargetSettingsService> = [.contacts]
    let rows = SimulatorPrivacyCommands.preiOS12ApprovalRows(forBundleIDs: bundleIDs, services: services)
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
    let rows = SimulatorPrivacyCommands.postiOS15ApprovalRows(forBundleIDs: bundleIDs, services: services)
    // auth_value=2 is required for AVCaptureDevice.authorizationStatus to return
    // something other than notDetermined
    XCTAssertTrue(
      rows.contains("0, 2, 2, 2"),
      "Post-iOS 15 must use auth_value=2 for AVCaptureDevice compatibility")
  }

  func testPostiOS17RowsIncludePidAndBootUuidColumns() {
    let bundleIDs: Set<String> = ["com.test.app"]
    let services: Set<FBTargetSettingsService> = [.microphone]
    let rows17 = SimulatorPrivacyCommands.postiOS17ApprovalRows(forBundleIDs: bundleIDs, services: services)
    let rows15 = SimulatorPrivacyCommands.postiOS15ApprovalRows(forBundleIDs: bundleIDs, services: services)
    XCTAssertGreaterThan(
      rows17.count, rows15.count,
      "iOS 17 rows should be longer than iOS 15 due to additional columns")
    XCTAssertTrue(
      rows17.contains("'UNUSED'"),
      "iOS 17 rows should contain boot_uuid placeholder")
  }

  func testPostiOS17InsertNamesColumnsForForwardCompatibility() {
    let schema = "CREATE TABLE access (last_reminded INTEGER, future_column_1 INTEGER DEFAULT 0, future_column_2 INTEGER DEFAULT 0)"
    let query = SimulatorPrivacyCommands.approvalInsertQuery(
      forAccessSchema: schema,
      bundleIDs: ["com.test.app"],
      services: [.microphone])

    XCTAssertTrue(
      query.hasPrefix("INSERT or REPLACE INTO access (service, client, client_type"),
      "Post-iOS 17 inserts should name columns instead of matching table width")
    XCTAssertTrue(
      query.contains("boot_uuid, last_reminded) VALUES"),
      "Post-iOS 17 inserts should cover every value emitted by the row builder")
    XCTAssertFalse(
      query.contains("INSERT or REPLACE INTO access VALUES"),
      "Post-iOS 17 inserts should allow newer columns to use their defaults")
  }

  func testPostiOS17InsertPairsEveryColumnNameWithExactlyOneValue() {
    let query = SimulatorPrivacyCommands.approvalInsertQuery(
      forAccessSchema: "CREATE TABLE access (last_reminded INTEGER)",
      bundleIDs: ["com.test.app"],
      services: [.microphone])

    guard let namesOpen = query.firstIndex(of: "("),
      let separator = query.range(of: ") VALUES ("),
      let valuesClose = query.lastIndex(of: ")")
    else {
      XCTFail("Could not parse the generated insert: \(query)")
      return
    }

    let names = query[query.index(after: namesOpen)..<separator.lowerBound]
      .components(separatedBy: ",")
      .map { $0.trimmingCharacters(in: .whitespaces) }
    let values = query[separator.upperBound..<valuesClose]
      .components(separatedBy: ",")
      .map { $0.trimmingCharacters(in: .whitespaces) }

    XCTAssertEqual(
      names.count, values.count,
      "Every named column needs exactly one value. An arity mismatch here is the same defect as the positional insert's 'table access has 19 columns but 17 values were supplied'")

    // Pinning the full list, not a prefix: INSERT or REPLACE substitutes the column default
    // rather than failing when a mis-paired NULL lands in a NOT NULL DEFAULT column, so a
    // transposition writes a row that exists but grants nothing, with no error.
    XCTAssertEqual(
      names,
      [
        "service",
        "client",
        "client_type",
        "auth_value",
        "auth_reason",
        "auth_version",
        "csreq",
        "policy_id",
        "indirect_object_identifier_type",
        "indirect_object_identifier",
        "indirect_object_code_identity",
        "flags",
        "last_modified",
        "pid",
        "pid_version",
        "boot_uuid",
        "last_reminded",
      ],
      "Column names must stay in the order postiOS17ApprovalRows emits its values")
  }

  func testApprovalRowsGenerateCorrectCountForMultipleInputs() {
    let bundleIDs: Set<String> = ["com.app1", "com.app2"]
    let services: Set<FBTargetSettingsService> = [.contacts, .photos]
    let rows = SimulatorPrivacyCommands.preiOS12ApprovalRows(forBundleIDs: bundleIDs, services: services)
    let tuples = rows.components(separatedBy: "), (")
    XCTAssertEqual(
      tuples.count, 4,
      "Should generate one tuple per bundleID-service combination (2x2=4)")
  }

  func testApprovalRowsFilterToTCCServicesOnly() {
    let bundleIDs: Set<String> = ["com.test.app"]
    let services: Set<FBTargetSettingsService> = [.contacts, .location]
    let rows = SimulatorPrivacyCommands.preiOS12ApprovalRows(forBundleIDs: bundleIDs, services: services)
    XCTAssertTrue(
      rows.contains("kTCCServiceAddressBook"),
      "Should include contacts which is in TCC mapping")
    XCTAssertFalse(
      rows.contains("location"),
      "Should not include location which is not in TCC mapping")
  }

  // MARK: - Grant/Revoke Access Input Validation

  func testGrantAccessRejectsEmptyServices() async {
    let simulator = makeSimulator()
    await assertThrowsAsync(
      "grantAccess should reject empty services set",
      {
        try await simulator.privacy.grantAccess(["com.test"], toServices: [])
      }
    ) { if case .noServicesToGrant = $0 { return true } else { return false } }
  }

  func testGrantAccessRejectsEmptyBundleIDs() async {
    let simulator = makeSimulator()
    await assertThrowsAsync(
      "grantAccess should reject empty bundle IDs set",
      {
        try await simulator.privacy.grantAccess([], toServices: [.contacts])
      }
    ) { if case .noBundleIDsToGrant = $0 { return true } else { return false } }
  }

  func testRevokeAccessRejectsEmptyServices() async {
    let simulator = makeSimulator()
    await assertThrowsAsync(
      "revokeAccess should reject empty services set",
      {
        try await simulator.privacy.revokeAccess(["com.test"], toServices: [])
      }
    ) { if case .noServicesToRevoke = $0 { return true } else { return false } }
  }

  func testRevokeAccessRejectsEmptyBundleIDs() async {
    let simulator = makeSimulator()
    await assertThrowsAsync(
      "revokeAccess should reject empty bundle IDs set",
      {
        try await simulator.privacy.revokeAccess([], toServices: [.contacts])
      }
    ) { if case .noBundleIDsToRevoke = $0 { return true } else { return false } }
  }

  // MARK: - Deeplink Access Validation

  func testGrantDeeplinkRejectsEmptyScheme() async {
    let simulator = makeSimulator()
    await assertThrowsAsync(
      "grantAccess(toDeeplink:) should reject empty scheme",
      {
        try await simulator.privacy.grantAccess(["com.test"], toDeeplink: "")
      }
    ) { if case .emptyScheme = $0 { return true } else { return false } }
  }

  func testGrantDeeplinkRejectsEmptyBundleIDs() async {
    let simulator = makeSimulator()
    await assertThrowsAsync(
      "grantAccess(toDeeplink:) should reject empty bundle IDs",
      {
        try await simulator.privacy.grantAccess([], toDeeplink: "myapp")
      }
    ) { if case .emptyBundleIDs = $0 { return true } else { return false } }
  }

  func testRevokeDeeplinkRejectsEmptyScheme() async {
    let simulator = makeSimulator()
    await assertThrowsAsync(
      "revokeAccess(toDeeplink:) should reject empty scheme",
      {
        try await simulator.privacy.revokeAccess(["com.test"], toDeeplink: "")
      }
    ) { if case .emptyScheme = $0 { return true } else { return false } }
  }

  func testRevokeDeeplinkRejectsEmptyBundleIDs() async {
    let simulator = makeSimulator()
    await assertThrowsAsync(
      "revokeAccess(toDeeplink:) should reject empty bundle IDs",
      {
        try await simulator.privacy.revokeAccess([], toDeeplink: "myapp")
      }
    ) { if case .emptyBundleIDs = $0 { return true } else { return false } }
  }
}

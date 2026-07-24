/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import XCTest

// MARK: - Tests

final class FBSimulatorSettingsCommandsTests: XCTestCase {

  // MARK: - Helpers

  private func makeSimulator() -> FBSimulator {
    let simulator = FBSimulatorTestSupport.testableSimulator()
    simulator.commandCache.register(FBSimulatorSettingsCommands(simulator: simulator), as: FBSimulatorSettingsCommands.self)
    return simulator
  }

  private func assertThrowsAsync(_ message: String, _ expression: () async throws -> Void) async {
    do {
      try await expression()
      XCTFail(message)
    } catch {
      // Expected to throw.
    }
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

  func testGrantAccessRejectsEmptyServices() async {
    let simulator = makeSimulator()
    await assertThrowsAsync("grantAccess should reject empty services set") {
      try await simulator.grantAccess(["com.test"], toServices: [])
    }
  }

  func testGrantAccessRejectsEmptyBundleIDs() async {
    let simulator = makeSimulator()
    await assertThrowsAsync("grantAccess should reject empty bundle IDs set") {
      try await simulator.grantAccess([], toServices: [.contacts])
    }
  }

  func testRevokeAccessRejectsEmptyServices() async {
    let simulator = makeSimulator()
    await assertThrowsAsync("revokeAccess should reject empty services set") {
      try await simulator.revokeAccess(["com.test"], toServices: [])
    }
  }

  func testRevokeAccessRejectsEmptyBundleIDs() async {
    let simulator = makeSimulator()
    await assertThrowsAsync("revokeAccess should reject empty bundle IDs set") {
      try await simulator.revokeAccess([], toServices: [.contacts])
    }
  }

  // MARK: - Deeplink Access Validation

  func testGrantDeeplinkRejectsEmptyScheme() async {
    let simulator = makeSimulator()
    await assertThrowsAsync("grantAccess(toDeeplink:) should reject empty scheme") {
      try await simulator.grantAccess(["com.test"], toDeeplink: "")
    }
  }

  func testGrantDeeplinkRejectsEmptyBundleIDs() async {
    let simulator = makeSimulator()
    await assertThrowsAsync("grantAccess(toDeeplink:) should reject empty bundle IDs") {
      try await simulator.grantAccess([], toDeeplink: "myapp")
    }
  }

  func testRevokeDeeplinkRejectsEmptyScheme() async {
    let simulator = makeSimulator()
    await assertThrowsAsync("revokeAccess(toDeeplink:) should reject empty scheme") {
      try await simulator.revokeAccess(["com.test"], toDeeplink: "")
    }
  }

  func testRevokeDeeplinkRejectsEmptyBundleIDs() async {
    let simulator = makeSimulator()
    await assertThrowsAsync("revokeAccess(toDeeplink:) should reject empty bundle IDs") {
      try await simulator.revokeAccess([], toDeeplink: "myapp")
    }
  }

  // MARK: - DNS Validation

  func testSetDnsServersRejectsEmptyArray() async {
    let simulator = makeSimulator()
    await assertThrowsAsync("setDnsServers should reject empty array") {
      try await simulator.setDnsServers([])
    }
  }

  // MARK: - FBSimulatorSettingResolution Parsing

  func testParseHardwareKeyboardEnableDisable() throws {
    XCTAssertEqual(try FBSimulatorSettingResolution(name: "hardware-keyboard", value: "enable", type: nil, domain: nil), .setting(.hardwareKeyboard(true)))
    XCTAssertEqual(try FBSimulatorSettingResolution(name: "hardware-keyboard", value: "disable", type: nil, domain: nil), .setting(.hardwareKeyboard(false)))
  }

  func testParseSlowAnimationsAndIncreaseContrast() throws {
    XCTAssertEqual(try FBSimulatorSettingResolution(name: "slow-animations", value: "enable", type: nil, domain: nil), .setting(.slowAnimations(true)))
    XCTAssertEqual(try FBSimulatorSettingResolution(name: "increase-contrast", value: "disable", type: nil, domain: nil), .setting(.increaseContrast(false)))
  }

  func testParseInvalidEnableDisableThrows() {
    XCTAssertThrowsError(try FBSimulatorSettingResolution(name: "hardware-keyboard", value: "on", type: nil, domain: nil))
  }

  func testParseAppearance() throws {
    XCTAssertEqual(try FBSimulatorSettingResolution(name: "appearance", value: "dark", type: nil, domain: nil), .setting(.appearance(.dark)))
    XCTAssertEqual(try FBSimulatorSettingResolution(name: "appearance", value: "light", type: nil, domain: nil), .setting(.appearance(.light)))
  }

  func testParseInvalidAppearanceThrows() {
    XCTAssertThrowsError(try FBSimulatorSettingResolution(name: "appearance", value: "purple", type: nil, domain: nil))
  }

  func testParseContentSize() throws {
    XCTAssertEqual(try FBSimulatorSettingResolution(name: "content-size", value: "large", type: nil, domain: nil), .setting(.contentSize(.large)))
    XCTAssertEqual(
      try FBSimulatorSettingResolution(name: "content-size", value: "accessibility-medium", type: nil, domain: nil),
      .setting(.contentSize(.accessibilityMedium)))
  }

  func testParseInvalidContentSizeThrows() {
    XCTAssertThrowsError(try FBSimulatorSettingResolution(name: "content-size", value: "gigantic", type: nil, domain: nil))
  }

  func testParseLocale() throws {
    XCTAssertEqual(try FBSimulatorSettingResolution(name: "locale", value: "en_US", type: nil, domain: nil), .setting(.locale(localeIdentifier: "en_US")))
  }

  func testParseAutofillPasswords() throws {
    XCTAssertEqual(try FBSimulatorSettingResolution(name: "autofill-passwords", value: "disable", type: nil, domain: nil), .setting(.autoFillPasswords(false)))
    XCTAssertEqual(try FBSimulatorSettingResolution(name: "autofill-passwords", value: "enable", type: nil, domain: nil), .setting(.autoFillPasswords(true)))
    XCTAssertThrowsError(try FBSimulatorSettingResolution(name: "autofill-passwords", value: "off", type: nil, domain: nil))
  }

  func testParseUnknownNameFallsBackToPreference() throws {
    XCTAssertEqual(
      try FBSimulatorSettingResolution(name: "com.example.Key", value: "1", type: "int", domain: "com.example"),
      .preference(name: "com.example.Key", value: "1", type: "int", domain: "com.example"))
  }

  func testArgumentNameRoundTrip() {
    XCTAssertEqual(FBSimulatorAppearance(argumentName: "dark"), FBSimulatorAppearance.dark)
    XCTAssertEqual(FBSimulatorAppearance.dark.argumentName, "dark")
    XCTAssertEqual(FBSimulatorContentSizeCategory(argumentName: "large"), FBSimulatorContentSizeCategory.large)
    XCTAssertEqual(FBSimulatorContentSizeCategory.large.argumentName, "large")
    XCTAssertNil(FBSimulatorAppearance(argumentName: "purple"))
  }

  func testPreferenceBacking() {
    XCTAssertEqual(FBSimulatorSettingKey.autoFillPasswords.preferenceBacking?.domain, "com.apple.WebUI")
    XCTAssertEqual(FBSimulatorSettingKey.autoFillPasswords.preferenceBacking?.key, "AutoFillPasswords")
    XCTAssertNil(FBSimulatorSettingKey.locale.preferenceBacking?.domain)
    XCTAssertEqual(FBSimulatorSettingKey.locale.preferenceBacking?.key, "AppleLocale")
    XCTAssertNil(FBSimulatorSettingKey.hardwareKeyboard.preferenceBacking)
    XCTAssertNil(FBSimulatorSettingKey.appearance.preferenceBacking)
  }
}

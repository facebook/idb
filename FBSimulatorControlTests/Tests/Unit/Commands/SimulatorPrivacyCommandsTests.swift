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

  private func makeSimulator() -> Simulator {
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

  // MARK: - Magic Deeplink Key

  func testMagicDeeplinkKeyFormatsCorrectly() {
    let key = SimulatorPrivacyCommands.magicDeeplinkKey(forScheme: "myapp")
    XCTAssertEqual(
      key, "com.apple.CoreSimulator.CoreSimulatorBridge-->myapp",
      "Deeplink key should use CoreSimulatorBridge prefix with --> separator")
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

  // MARK: - Guest Invocations

  func testEveryTCCServiceMapsToItsGuestName() {
    let invocations = SimulatorPrivacyCommands.privacyInvocations(
      bundleIDs: ["com.test"],
      services: [.camera, .microphone, .photos, .contacts],
      approve: true)

    XCTAssertEqual(
      invocations,
      [.init(action: "approve", arguments: ["com.test", "camera", "contacts", "microphone", "photos"])])
  }

  func testServicesAreBatchedIntoOneCallPerBundleID() {
    let invocations = SimulatorPrivacyCommands.privacyInvocations(
      bundleIDs: ["com.b", "com.a"],
      services: [.camera, .photos],
      approve: true)

    XCTAssertEqual(
      invocations,
      [
        .init(action: "approve", arguments: ["com.a", "camera", "photos"]),
        .init(action: "approve", arguments: ["com.b", "camera", "photos"]),
      ],
      "Each bundle id gets one call carrying every service, ordered for a comparable trace")
  }

  func testRevokeUsesTheRevokeAction() {
    let invocations = SimulatorPrivacyCommands.privacyInvocations(
      bundleIDs: ["com.test"],
      services: [.contacts],
      approve: false)

    XCTAssertEqual(invocations, [.init(action: "revoke", arguments: ["com.test", "contacts"])])
  }

  func testServicesTheGuestDoesNotHandleAreNotSentToIt() {
    let invocations = SimulatorPrivacyCommands.privacyInvocations(
      bundleIDs: ["com.test"],
      services: [.camera, .location],
      approve: true)

    XCTAssertEqual(
      invocations,
      [.init(action: "approve", arguments: ["com.test", "camera"])],
      "Location is routed through CoreSimulator, not the guest")
  }
}

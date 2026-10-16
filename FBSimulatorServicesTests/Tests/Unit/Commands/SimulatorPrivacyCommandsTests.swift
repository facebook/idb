/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
@testable import FBSimulatorServices
import Foundation
import Testing

@Suite
struct SimulatorPrivacyCommandsTests {

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
      Issue.record(Comment(rawValue: message))
    } catch let error as SimulatorPrivacyError where isExpected(error) {
      // Expected.
    } catch {
      Issue.record("\(message); threw \(error)")
    }
  }

  // MARK: - Magic Deeplink Key

  @Test
  func magicDeeplinkKeyFormatsCorrectly() {
    let key = SimulatorPrivacyCommands.magicDeeplinkKey(forScheme: "myapp")
    #expect(key == "com.apple.CoreSimulator.CoreSimulatorBridge-->myapp", "Deeplink key should use CoreSimulatorBridge prefix with --> separator")
  }

  // MARK: - Grant/Revoke Access Input Validation

  @Test
  func grantAccessRejectsEmptyServices() async {
    let simulator = makeSimulator()
    await assertThrowsAsync(
      "grantAccess should reject empty services set",
      {
        try await simulator.privacy.grantAccess(["com.test"], toServices: [])
      }
    ) { if case .noServicesToGrant = $0 { return true } else { return false } }
  }

  @Test
  func grantAccessRejectsEmptyBundleIDs() async {
    let simulator = makeSimulator()
    await assertThrowsAsync(
      "grantAccess should reject empty bundle IDs set",
      {
        try await simulator.privacy.grantAccess([], toServices: [.contacts])
      }
    ) { if case .noBundleIDsToGrant = $0 { return true } else { return false } }
  }

  @Test
  func revokeAccessRejectsEmptyServices() async {
    let simulator = makeSimulator()
    await assertThrowsAsync(
      "revokeAccess should reject empty services set",
      {
        try await simulator.privacy.revokeAccess(["com.test"], toServices: [])
      }
    ) { if case .noServicesToRevoke = $0 { return true } else { return false } }
  }

  @Test
  func revokeAccessRejectsEmptyBundleIDs() async {
    let simulator = makeSimulator()
    await assertThrowsAsync(
      "revokeAccess should reject empty bundle IDs set",
      {
        try await simulator.privacy.revokeAccess([], toServices: [.contacts])
      }
    ) { if case .noBundleIDsToRevoke = $0 { return true } else { return false } }
  }

  // MARK: - Deeplink Access Validation

  @Test
  func grantDeeplinkRejectsEmptyScheme() async {
    let simulator = makeSimulator()
    await assertThrowsAsync(
      "grantAccess(toDeeplink:) should reject empty scheme",
      {
        try await simulator.privacy.grantAccess(["com.test"], toDeeplink: "")
      }
    ) { if case .emptyScheme = $0 { return true } else { return false } }
  }

  @Test
  func grantDeeplinkRejectsEmptyBundleIDs() async {
    let simulator = makeSimulator()
    await assertThrowsAsync(
      "grantAccess(toDeeplink:) should reject empty bundle IDs",
      {
        try await simulator.privacy.grantAccess([], toDeeplink: "myapp")
      }
    ) { if case .emptyBundleIDs = $0 { return true } else { return false } }
  }

  @Test
  func revokeDeeplinkRejectsEmptyScheme() async {
    let simulator = makeSimulator()
    await assertThrowsAsync(
      "revokeAccess(toDeeplink:) should reject empty scheme",
      {
        try await simulator.privacy.revokeAccess(["com.test"], toDeeplink: "")
      }
    ) { if case .emptyScheme = $0 { return true } else { return false } }
  }

  @Test
  func revokeDeeplinkRejectsEmptyBundleIDs() async {
    let simulator = makeSimulator()
    await assertThrowsAsync(
      "revokeAccess(toDeeplink:) should reject empty bundle IDs",
      {
        try await simulator.privacy.revokeAccess([], toDeeplink: "myapp")
      }
    ) { if case .emptyBundleIDs = $0 { return true } else { return false } }
  }

  // MARK: - Guest Invocations

  @Test
  func everyTCCServiceMapsToItsGuestName() {
    let invocations = SimulatorPrivacyCommands.privacyInvocations(
      bundleIDs: ["com.test"],
      services: [.camera, .microphone, .photos, .contacts],
      approve: true)

    #expect(invocations == [.init(action: "approve", arguments: ["com.test", "camera", "contacts", "microphone", "photos"])])
  }

  @Test
  func servicesAreBatchedIntoOneCallPerBundleID() {
    let invocations = SimulatorPrivacyCommands.privacyInvocations(
      bundleIDs: ["com.b", "com.a"],
      services: [.camera, .photos],
      approve: true)

    #expect(
      invocations == [
        .init(action: "approve", arguments: ["com.a", "camera", "photos"]),
        .init(action: "approve", arguments: ["com.b", "camera", "photos"]),
      ],
      "Each bundle id gets one call carrying every service, ordered for a comparable trace")
  }

  @Test
  func revokeUsesTheRevokeAction() {
    let invocations = SimulatorPrivacyCommands.privacyInvocations(
      bundleIDs: ["com.test"],
      services: [.contacts],
      approve: false)

    #expect(invocations == [.init(action: "revoke", arguments: ["com.test", "contacts"])])
  }

  @Test
  func servicesTheGuestDoesNotHandleAreNotSentToIt() {
    let invocations = SimulatorPrivacyCommands.privacyInvocations(
      bundleIDs: ["com.test"],
      services: [.camera, .location],
      approve: true)

    #expect(invocations == [.init(action: "approve", arguments: ["com.test", "camera"])], "Location is routed through CoreSimulator, not the guest")
  }
}

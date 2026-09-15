/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
@_implementationOnly import SimulatorFrameworkBridgeLib
import XCTest

private let legacyAuthorizationSelector = "setAuthorizationStatuses:authorizationModes:forBundleIdentifier:options:completion:"
private let modeInfosAuthorizationSelector = "setAuthorizationStatuses:authorizationModes:modeInfos:forBundleIdentifier:options:completion:"

final class HealthSettingsServiceTests: XCTestCase {

  // HealthKit is present in the simulator, so every action reaches a real HKAuthorizationStore
  // and healthd. `com.example.test` is not an installed app, which is why the read verbs report
  // failure rather than returning records.
  func testListReportsFailureForAnUnknownBundleIdentifier() {
    XCTAssertEqual(handleHealthSettingsAction("list", "com.example.test", []), 1)
  }

  func testClearReportsFailureForAnUnknownBundleIdentifier() {
    XCTAssertEqual(handleHealthSettingsAction("clear", "com.example.test", []), 1)
  }

  // MARK: - The drifted authorization selector

  // `approve` and `revoke` answer with an exit code on every runtime, whichever spelling of
  // `setAuthorizationStatuses:…` it declares.
  func testApproveAnswersWithAStatusOnAnyRuntime() {
    XCTAssertNil(FBHealthApproveException(["HKQuantityTypeIdentifierStepCount"]))
  }

  func testApproveWithDefaultTypesAnswersWithAStatusOnAnyRuntime() {
    XCTAssertNil(FBHealthApproveException([]))
  }

  // Exactly one of the two spellings is present on any runtime, so the service's
  // `respondsToSelector:` dispatch between them is total. A third rename shows up as a failure here.
  func testTheRuntimeDeclaresExactlyOneAuthorizationSpelling() {
    XCTAssertNotNil(FBHealthAuthorizationStoreClass(), "HealthKit failed to load")
    let legacy = FBHealthRuntimeDeclaresSelector(legacyAuthorizationSelector)
    let modeInfos = FBHealthRuntimeDeclaresSelector(modeInfosAuthorizationSelector)
    XCTAssertNotEqual(
      legacy,
      modeInfos,
      "expected one spelling, got legacy=\(legacy) modeInfos=\(modeInfos)"
    )
  }

  // The header declares whichever spelling the runtime reports, with `options:` as the integer both
  // take. A rename or a retyped argument is a red test here rather than a silent miscompile at the send.
  func testTheDeclaredAuthorizationSignatureAgreesWithTheRuntime() {
    let legacy = FBHealthRuntimeDeclaresSelector(legacyAuthorizationSelector)
    let declared = legacy ? legacyAuthorizationSelector : modeInfosAuthorizationSelector
    let expected = legacy ? "v@:@@@Q@?" : "v@:@@@@Q@?"
    let mismatch = FBAXSignatureMismatch("HKAuthorizationStore", declared, false, expected)
    XCTAssertNil(mismatch, "\(String(describing: mismatch))")
  }

  func testUnknownActionReturnsFailure() {
    XCTAssertEqual(handleHealthSettingsAction("unknown", "com.example.test", []), 1)
  }
}

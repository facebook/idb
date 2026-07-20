/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Testing

/// Tests the pure version-flooring logic that picks the deployment target for
/// injected code: the runtime OS version, clamped to the local SDK version.
@Suite
struct CompilerEnvironmentTests {

  // MARK: - floored

  @Test
  func runtimeOlderThanSDKIsUsed() {
    // The motivating case: SDK 27.0 locally, simulator on 26.2 -> build for 26.2.
    #expect(DeploymentTargetVersion.floored(runtimeOSVersion: "26.2", sdkVersion: "27.0") == "26.2")
  }

  @Test
  func runtimeNewerThanSDKIsClampedToSDK() {
    // Older Xcode against a newer runtime: can't deploy above the SDK.
    #expect(DeploymentTargetVersion.floored(runtimeOSVersion: "27.0", sdkVersion: "26.4") == "26.4")
  }

  @Test
  func runtimeEqualToSDKIsUsed() {
    #expect(DeploymentTargetVersion.floored(runtimeOSVersion: "27.0", sdkVersion: "27.0") == "27.0")
  }

  @Test
  func flooringComparesNumericallyNotLexically() {
    // "9.0" is older than "10.0" even though "9" > "1" as text.
    #expect(DeploymentTargetVersion.floored(runtimeOSVersion: "9.0", sdkVersion: "10.0") == "9.0")
    #expect(DeploymentTargetVersion.floored(runtimeOSVersion: "10.0", sdkVersion: "9.0") == "9.0")
  }

  @Test
  func flooringTreatsMissingComponentsAsZero() {
    #expect(DeploymentTargetVersion.floored(runtimeOSVersion: "26", sdkVersion: "26.2") == "26")
    #expect(DeploymentTargetVersion.floored(runtimeOSVersion: "26.2", sdkVersion: "26") == "26")
  }

  // MARK: - isAtMost

  @Test
  func isAtMostOrdersMajorMinor() {
    #expect(DeploymentTargetVersion.isAtMost("26.2", "27.0"))
    #expect(!DeploymentTargetVersion.isAtMost("27.0", "26.2"))
  }

  @Test
  func isAtMostIsTrueForEqualVersions() {
    #expect(DeploymentTargetVersion.isAtMost("27.0", "27.0"))
    #expect(DeploymentTargetVersion.isAtMost("26.2.3", "26.2.3"))
  }

  @Test
  func isAtMostComparesEachComponentNumerically() {
    // Not lexicographic: "9" < "10".
    #expect(DeploymentTargetVersion.isAtMost("9.0", "10.0"))
    #expect(!DeploymentTargetVersion.isAtMost("10.0", "9.0"))
  }

  @Test
  func isAtMostPadsMissingComponentsWithZero() {
    #expect(DeploymentTargetVersion.isAtMost("26", "26.2")) // 26.0 <= 26.2
    #expect(!DeploymentTargetVersion.isAtMost("26.2", "26")) // 26.2 > 26.0
    #expect(DeploymentTargetVersion.isAtMost("26.2", "26.2.0")) // trailing zero is equal
    #expect(!DeploymentTargetVersion.isAtMost("26.2.1", "26.2")) // 26.2.1 > 26.2.0
  }
}

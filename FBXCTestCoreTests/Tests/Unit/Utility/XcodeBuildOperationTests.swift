/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBXCTestCore
import Foundation
import Testing

@Suite
struct XcodeBuildOperationTests {

  @Test
  func uiTestConfiguration() {
    let testHostPath = "/tmp/test_host_path.app"
    let testHostBundle = BundleDescriptor(name: "test.host.app", identifier: "test.host.app", path: testHostPath, binary: nil)

    let testBundlePath = "/tmp/test_host_path.app/test_bundle_path.xctest"
    let testBundle = BundleDescriptor(name: "test.bundle", identifier: "test.bundle", path: testBundlePath, binary: nil)

    let appLaunch = ApplicationLaunchConfiguration(
      bundleID: "com.bundle.id",
      bundleName: "BundleName",
      arguments: [],
      environment: [:],
      waitForDebugger: false,
      launchMode: .failIfRunning
    )

    let configuration = TestLaunchConfiguration(
      testBundle: testBundle,
      applicationLaunchConfiguration: appLaunch,
      testHostBundle: testHostBundle,
      timeout: 0,
      initializeUITesting: false,
      useXcodebuild: false,
      testsToRun: nil,
      testsToSkip: nil,
      targetApplicationBundle: nil,
      xcTestRunProperties: nil,
      resultBundlePath: nil,
      reportActivities: false,
      coverageDirectoryPath: nil,
      enableContinuousCoverageCollection: false,
      logDirectoryPath: nil,
      reportResultBundle: false
    )

    let properties = XcodeBuildOperation.xctestRunProperties(configuration) as [String: Any]
    let stubBundleProperties = properties["StubBundleId"] as! [String: Any]

    #expect(stubBundleProperties["TestHostPath"] as? String == testHostPath)
    #expect(stubBundleProperties["TestBundlePath"] as? String == testBundlePath)
    #expect(stubBundleProperties["UseUITargetAppProvidedByTests"] as? NSNumber == true)
    #expect(stubBundleProperties["IsUITestBundle"] as? NSNumber == true)
  }

  private func target(
    environment: [String: String] = [:], testing: [String: String] = [:], application: [String: String]? = nil
  ) -> [String: Any] {
    var properties: [String: Any] = [
      "TestBundlePath": "/tmp/fixture.xctest", "IsUITestBundle": true,
      "EnvironmentVariables": environment, "TestingEnvironmentVariables": testing,
    ]
    if let application { properties["UITargetAppEnvironmentVariables"] = application }
    return properties
  }

  @Test
  func xcodebuildDefaultsRunnerAndAUTWithoutChangingMetadata() throws {
    let original: [String: Any] = ["test": target(environment: ["MAGIC": "keep"]), "__xctestrun_metadata__": ["FormatVersion": 1]]
    let updated = XcodeBuildOperation.unarmedAudioInjectionProperties(original, applicationEnvironment: [:])
    let test = try #require(updated["test"] as? [String: Any])
    #expect(test["EnvironmentVariables"] as? [String: String] == ["MAGIC": "keep", "IDB_AUDIO_INJECTION": "0"])
    #expect(test["UITargetAppEnvironmentVariables"] as? [String: String] == ["IDB_AUDIO_INJECTION": "0"])
    #expect(updated["__xctestrun_metadata__"] as? NSDictionary == original["__xctestrun_metadata__"] as? NSDictionary)
  }

  @Test
  func importedArmingSurvivesEnvironmentMapReplacement() throws {
    let base = [
      "test": target(
        environment: ["IDB_AUDIO_INJECTION": "1", "OLD": "drop"], testing: ["IDB_AUDIO_INJECTION": "1"],
        application: ["IDB_AUDIO_INJECTION": "0", "AUT": "keep"])
    ]
    let generated = ["StubBundleId": target(environment: ["NEW": "keep"], testing: ["SDK": "keep"])]
    let merged = XcodeBuildOperation.overwriteXCTestRunProperties(withBaseProperties: base, newProperties: generated)
    let updated = XcodeBuildOperation.unarmedAudioInjectionProperties(merged, applicationEnvironment: [:])
    let test = try #require(updated["test"] as? [String: Any])
    #expect(test["EnvironmentVariables"] as? [String: String] == ["NEW": "keep", "IDB_AUDIO_INJECTION": "1"])
    #expect(test["TestingEnvironmentVariables"] as? [String: String] == ["SDK": "keep", "IDB_AUDIO_INJECTION": "1"])
    #expect(test["UITargetAppEnvironmentVariables"] as? [String: String] == ["IDB_AUDIO_INJECTION": "0", "AUT": "keep"])
  }

  @Test
  func explicitConfigurationOverridesImportedRunnerArming() throws {
    let requested = ["IDB_AUDIO_INJECTION": "0"]
    let base = ["test": target(environment: ["IDB_AUDIO_INJECTION": "1"], testing: ["IDB_AUDIO_INJECTION": "1"])]
    let generated = ["StubBundleId": target(environment: requested)]
    let merged = XcodeBuildOperation.overwriteXCTestRunProperties(withBaseProperties: base, newProperties: generated)
    let updated = XcodeBuildOperation.unarmedAudioInjectionProperties(merged, applicationEnvironment: requested)
    let test = try #require(updated["test"] as? [String: Any])
    #expect(test["EnvironmentVariables"] as? [String: String] == requested)
    #expect((test["TestingEnvironmentVariables"] as? [String: String])?["IDB_AUDIO_INJECTION"] == nil)
    #expect(test["UITargetAppEnvironmentVariables"] as? [String: String] == requested)
  }

  @Test
  func testingMapOptInIsNotOverriddenByARunnerDefault() throws {
    let updated = XcodeBuildOperation.unarmedAudioInjectionProperties(
      ["test": target(testing: ["IDB_AUDIO_INJECTION": "1"])], applicationEnvironment: [:])
    let test = try #require(updated["test"] as? [String: Any])
    #expect((test["EnvironmentVariables"] as? [String: String])?["IDB_AUDIO_INJECTION"] == nil)
    #expect((test["TestingEnvironmentVariables"] as? [String: String])?["IDB_AUDIO_INJECTION"] == "1")
  }

  @Test
  func autOptInPreservesItsOwnOverride() throws {
    let requested = ["IDB_AUDIO_INJECTION": "1"]
    let updated = XcodeBuildOperation.unarmedAudioInjectionProperties(
      ["test": target(environment: requested, application: ["IDB_AUDIO_INJECTION": "0"])], applicationEnvironment: requested)
    let test = try #require(updated["test"] as? [String: Any])
    #expect((test["EnvironmentVariables"] as? [String: String])?["IDB_AUDIO_INJECTION"] == "1")
    #expect((test["UITargetAppEnvironmentVariables"] as? [String: String])?["IDB_AUDIO_INJECTION"] == "0")
  }
}

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
struct TestRunnerConfigurationTests {

  @Test
  func launchEnvironment() {
    let testBundleBinary = BinaryDescriptor(name: "TestBinaryName", architectures: Set(), uuid: UUID(), path: "/blackhole/xctwda.xctest/test")
    let testBundle = BundleDescriptor(name: "TestBundleName", identifier: "TestBundleIdentifier", path: "/blackhole/xctwda.xctest", binary: testBundleBinary)

    let hostApplicationBinary = BinaryDescriptor(name: "HostApplicationBinaryName", architectures: Set(), uuid: UUID(), path: "/blackhole/pray.app/app")
    let hostApplication = BundleDescriptor(
      name: "HostApplicationName",
      identifier: "HostApplicationIdentifier",
      path: "/blackhole/pray.app",
      binary: hostApplicationBinary
    )

    let expected: [String: String] = [
      "AppTargetLocation": "/blackhole/pray.app/app",
      "DYLD_FALLBACK_FRAMEWORK_PATH": "/Apple",
      "DYLD_FALLBACK_LIBRARY_PATH": "/Apple",
      "OBJC_DISABLE_GC": "YES",
      "IDB_AUDIO_INJECTION": "0",
      "MAGIC": "IS_HERE",
      "TestBundleLocation": "/blackhole/xctwda.xctest",
      "XCODE_DBG_XPC_EXCLUSIONS": "com.apple.dt.xctestSymbolicator",
      "XCTestConfigurationFilePath": "/booo/magic.xctestconfiguration",
    ]
    let actual = TestRunnerConfiguration.launchEnvironment(
      withHostApplication: hostApplication,
      hostApplicationAdditionalEnvironment: ["MAGIC": "IS_HERE"],
      testBundle: testBundle,
      testConfigurationPath: "/booo/magic.xctestconfiguration",
      frameworkSearchPaths: ["/Apple"]
    )
    #expect((expected as NSDictionary) == (actual as NSDictionary))
  }

  @Test
  func ordinaryTestEnvironmentDefaultsToUnarmed() {
    let environment = XCTestShimConfiguration.unarmedAudioInjectionEnvironment(["DYLD_INSERT_LIBRARIES": "test-shim", "MAGIC": "keep"])
    #expect(environment == ["DYLD_INSERT_LIBRARIES": "test-shim", "MAGIC": "keep", "IDB_AUDIO_INJECTION": "0"])
  }

  @Test
  func explicitTestArmingValuesArePreserved() {
    for value in ["1", "0", "", "custom"] {
      #expect(
        XCTestShimConfiguration.unarmedAudioInjectionEnvironment(["IDB_AUDIO_INJECTION": value])["IDB_AUDIO_INJECTION"] == value)
    }
  }

  @Test
  func customOptInIsNotOverwrittenByDefault() {
    let custom = TestRunnerConfiguration.addAdditionalEnvironmentVariables(
      ["MAGIC": "keep"], source: ["CUSTOM_IDB_AUDIO_INJECTION": "1", "IGNORED": "value"])
    #expect(
      XCTestShimConfiguration.unarmedAudioInjectionEnvironment(custom)
        == ["MAGIC": "keep", "IDB_AUDIO_INJECTION": "1"])
  }

  @Test
  func testedApplicationReceivesResolvedTestArmingIntent() {
    let original = ["DYLD_INSERT_LIBRARIES": "bootstrap", "LLVM_PROFILE_FILE": "coverage"]
    let defaulted = TestRunnerConfiguration.audioInjectionTestedApplicationEnvironment(
      original, applicationEnvironment: [:], runnerEnvironment: [:])
    #expect(defaulted["IDB_AUDIO_INJECTION"] == "0")
    let optedIn = TestRunnerConfiguration.audioInjectionTestedApplicationEnvironment(
      original, applicationEnvironment: ["IDB_AUDIO_INJECTION": "1"], runnerEnvironment: ["IDB_AUDIO_INJECTION": "0"])
    #expect(optedIn["IDB_AUDIO_INJECTION"] == "1")
    let explicitZero = TestRunnerConfiguration.audioInjectionTestedApplicationEnvironment(
      original, applicationEnvironment: ["IDB_AUDIO_INJECTION": "0"], runnerEnvironment: ["IDB_AUDIO_INJECTION": "1"])
    #expect(explicitZero["IDB_AUDIO_INJECTION"] == "0")
    #expect(explicitZero["DYLD_INSERT_LIBRARIES"] == "bootstrap")
    #expect(explicitZero["LLVM_PROFILE_FILE"] == "coverage")
  }
}

/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBXCTestCore
import XCTest

final class TestRunnerConfigurationTests: XCTestCase {

  func testLaunchEnvironment() {
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
    XCTAssertEqual(expected as NSDictionary, actual as NSDictionary)
  }

  func testOrdinaryTestEnvironmentDefaultsToUnarmed() {
    let environment = XCTestShimConfiguration.unarmedAudioInjectionEnvironment(["DYLD_INSERT_LIBRARIES": "test-shim", "MAGIC": "keep"])
    XCTAssertEqual(environment, ["DYLD_INSERT_LIBRARIES": "test-shim", "MAGIC": "keep", "IDB_AUDIO_INJECTION": "0"])
  }

  func testExplicitTestArmingValuesArePreserved() {
    for value in ["1", "0", "", "custom"] {
      XCTAssertEqual(
        XCTestShimConfiguration.unarmedAudioInjectionEnvironment(["IDB_AUDIO_INJECTION": value])["IDB_AUDIO_INJECTION"], value)
    }
  }

  func testCustomOptInIsNotOverwrittenByDefault() {
    let custom = TestRunnerConfiguration.addAdditionalEnvironmentVariables(
      ["MAGIC": "keep"], source: ["CUSTOM_IDB_AUDIO_INJECTION": "1", "IGNORED": "value"])
    XCTAssertEqual(
      XCTestShimConfiguration.unarmedAudioInjectionEnvironment(custom),
      ["MAGIC": "keep", "IDB_AUDIO_INJECTION": "1"])
  }

  func testTestedApplicationReceivesResolvedTestArmingIntent() {
    let original = ["DYLD_INSERT_LIBRARIES": "bootstrap", "LLVM_PROFILE_FILE": "coverage"]
    let defaulted = TestRunnerConfiguration.audioInjectionTestedApplicationEnvironment(
      original, applicationEnvironment: [:], runnerEnvironment: [:])
    XCTAssertEqual(defaulted["IDB_AUDIO_INJECTION"], "0")
    let optedIn = TestRunnerConfiguration.audioInjectionTestedApplicationEnvironment(
      original, applicationEnvironment: ["IDB_AUDIO_INJECTION": "1"], runnerEnvironment: ["IDB_AUDIO_INJECTION": "0"])
    XCTAssertEqual(optedIn["IDB_AUDIO_INJECTION"], "1")
    let explicitZero = TestRunnerConfiguration.audioInjectionTestedApplicationEnvironment(
      original, applicationEnvironment: ["IDB_AUDIO_INJECTION": "0"], runnerEnvironment: ["IDB_AUDIO_INJECTION": "1"])
    XCTAssertEqual(explicitZero["IDB_AUDIO_INJECTION"], "0")
    XCTAssertEqual(explicitZero["DYLD_INSERT_LIBRARIES"], "bootstrap")
    XCTAssertEqual(explicitZero["LLVM_PROFILE_FILE"], "coverage")
  }
}

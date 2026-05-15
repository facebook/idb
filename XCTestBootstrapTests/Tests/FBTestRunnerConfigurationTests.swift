/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import XCTest
import XCTestBootstrap

final class FBTestRunnerConfigurationTests: XCTestCase {

  func testLaunchEnvironment() {
    let testBundleBinary = FBBinaryDescriptor(name: "TestBinaryName", architectures: Set(), uuid: UUID(), path: "/blackhole/xctwda.xctest/test")
    let testBundle = FBBundleDescriptor(name: "TestBundleName", identifier: "TestBundleIdentifier", path: "/blackhole/xctwda.xctest", binary: testBundleBinary)

    let hostApplicationBinary = FBBinaryDescriptor(name: "HostApplicationBinaryName", architectures: Set(), uuid: UUID(), path: "/blackhole/pray.app/app")
    let hostApplication = FBBundleDescriptor(
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
      "MAGIC": "IS_HERE",
      "TestBundleLocation": "/blackhole/xctwda.xctest",
      "XCODE_DBG_XPC_EXCLUSIONS": "com.apple.dt.xctestSymbolicator",
      "XCTestConfigurationFilePath": "/booo/magic.xctestconfiguration",
    ]
    let actual = FBTestRunnerConfiguration.launchEnvironment(
      withHostApplication: hostApplication,
      hostApplicationAdditionalEnvironment: ["MAGIC": "IS_HERE"],
      testBundle: testBundle,
      testConfigurationPath: "/booo/magic.xctestconfiguration",
      frameworkSearchPaths: ["/Apple"]
    )
    XCTAssertEqual(expected as NSDictionary, actual as NSDictionary)
  }
}

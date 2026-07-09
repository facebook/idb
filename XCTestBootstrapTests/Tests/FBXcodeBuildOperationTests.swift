/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import XCTest
import XCTestBootstrap

final class FBXcodeBuildOperationTests: XCTestCase {

  func testUITestConfiguration() {
    let testHostPath = "/tmp/test_host_path.app"
    let testHostBundle = FBBundleDescriptor(name: "test.host.app", identifier: "test.host.app", path: testHostPath, binary: nil)

    let testBundlePath = "/tmp/test_host_path.app/test_bundle_path.xctest"
    let testBundle = FBBundleDescriptor(name: "test.bundle", identifier: "test.bundle", path: testBundlePath, binary: nil)

    let appLaunch = FBApplicationLaunchConfiguration(
      bundleID: "com.bundle.id",
      bundleName: "BundleName",
      arguments: [],
      environment: [:],
      waitForDebugger: false,
      io: FBProcessIO<AnyObject, AnyObject, AnyObject>.outputToDevNull(),
      launchMode: .failIfRunning
    )

    let configuration = FBTestLaunchConfiguration(
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

    let properties = FBXcodeBuildOperation.xctestRunProperties(configuration) as [String: Any]
    let stubBundleProperties = properties["StubBundleId"] as! [String: Any]

    XCTAssertEqual(stubBundleProperties["TestHostPath"] as? String, testHostPath)
    XCTAssertEqual(stubBundleProperties["TestBundlePath"] as? String, testBundlePath)
    XCTAssertEqual(stubBundleProperties["UseUITargetAppProvidedByTests"] as? NSNumber, true)
    XCTAssertEqual(stubBundleProperties["IsUITestBundle"] as? NSNumber, true)
  }
}

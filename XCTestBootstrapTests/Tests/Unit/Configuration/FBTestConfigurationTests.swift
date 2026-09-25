/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest
import XCTestBootstrap

final class FBTestConfigurationTests: XCTestCase {

  func testSaveAs() throws {
    let sessionIdentifier = UUID()
    let someRandomPath = NSTemporaryDirectory()

    let testConfiguration = try FBTestConfigurationTestHelper.createTestConfigurationByWritingToFile(
      withSessionIdentifier: sessionIdentifier,
      moduleName: "ModuleName",
      testBundlePath: someRandomPath,
      uiTesting: true,
      testsToRun: Set(),
      testsToSkip: Set(),
      targetApplicationPath: "targetAppPath",
      targetApplicationBundleID: "targetBundleID",
      testApplicationDependencies: nil,
      automationFrameworkPath: nil,
      reportActivities: false
    )

    XCTAssertTrue(FileManager.default.fileExists(atPath: testConfiguration.path))

    let xcTestConfig = try XCTUnwrap(
      FBTestConfigurationTestHelper.xcTestConfiguration(testConfiguration))

    XCTAssertEqual(FBTestConfigurationTestHelper.productModuleName(xcTestConfig), "ModuleName")
    XCTAssertEqual(FBTestConfigurationTestHelper.testBundleURL(xcTestConfig), URL(fileURLWithPath: someRandomPath))
    XCTAssertEqual(FBTestConfigurationTestHelper.initialize(forUITesting: xcTestConfig), true)
    XCTAssertEqual(FBTestConfigurationTestHelper.targetApplicationPath(xcTestConfig), "targetAppPath")
    XCTAssertEqual(FBTestConfigurationTestHelper.targetApplicationBundleID(xcTestConfig), "targetBundleID")
    XCTAssertEqual(FBTestConfigurationTestHelper.reportActivities(xcTestConfig), false)
    XCTAssertEqual(FBTestConfigurationTestHelper.reportResults(toIDE: xcTestConfig), true)

    let capabilities: NSDictionary = ["XCTIssue capability": 1, "ubiquitous test identifiers": 1]
    XCTAssertEqual(FBTestConfigurationTestHelper.ideCapabilitiesDictionary(xcTestConfig)! as NSDictionary, capabilities)
  }
}

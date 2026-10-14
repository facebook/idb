/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBXCTestCore
import Foundation
import Testing

@Suite
struct FBTestConfigurationTests {

  @Test
  func saveAs() throws {
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

    #expect(FileManager.default.fileExists(atPath: testConfiguration.path))

    let xcTestConfig = try #require(FBTestConfigurationTestHelper.xcTestConfiguration(testConfiguration))

    #expect(FBTestConfigurationTestHelper.productModuleName(xcTestConfig) == "ModuleName")
    #expect(FBTestConfigurationTestHelper.testBundleURL(xcTestConfig) == URL(fileURLWithPath: someRandomPath))
    #expect(FBTestConfigurationTestHelper.initialize(forUITesting: xcTestConfig) == true)
    #expect(FBTestConfigurationTestHelper.targetApplicationPath(xcTestConfig) == "targetAppPath")
    #expect(FBTestConfigurationTestHelper.targetApplicationBundleID(xcTestConfig) == "targetBundleID")
    #expect(FBTestConfigurationTestHelper.reportActivities(xcTestConfig) == false)
    #expect(FBTestConfigurationTestHelper.reportResults(toIDE: xcTestConfig) == true)

    let capabilities: NSDictionary = ["XCTIssue capability": 1, "ubiquitous test identifiers": 1]
    #expect(FBTestConfigurationTestHelper.ideCapabilitiesDictionary(xcTestConfig)! as NSDictionary == capabilities)
  }
}

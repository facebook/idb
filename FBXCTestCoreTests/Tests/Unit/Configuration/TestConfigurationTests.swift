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
struct TestConfigurationTests {

  @Test
  func saveAs() throws {
    let sessionIdentifier = UUID()
    let someRandomPath = NSTemporaryDirectory()

    let testConfiguration = try TestConfigurationTestHelper.createTestConfigurationByWritingToFile(
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

    let xcTestConfig = try #require(TestConfigurationTestHelper.xcTestConfiguration(testConfiguration))

    #expect(TestConfigurationTestHelper.productModuleName(xcTestConfig) == "ModuleName")
    #expect(TestConfigurationTestHelper.testBundleURL(xcTestConfig) == URL(fileURLWithPath: someRandomPath))
    #expect(TestConfigurationTestHelper.initialize(forUITesting: xcTestConfig) == true)
    #expect(TestConfigurationTestHelper.targetApplicationPath(xcTestConfig) == "targetAppPath")
    #expect(TestConfigurationTestHelper.targetApplicationBundleID(xcTestConfig) == "targetBundleID")
    #expect(TestConfigurationTestHelper.reportActivities(xcTestConfig) == false)
    #expect(TestConfigurationTestHelper.reportResults(toIDE: xcTestConfig) == true)

    let capabilities: NSDictionary = ["XCTIssue capability": 1, "ubiquitous test identifiers": 1]
    #expect(TestConfigurationTestHelper.ideCapabilitiesDictionary(xcTestConfig)! as NSDictionary == capabilities)
  }
}

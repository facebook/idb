/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBXCTestCore
import Foundation

/// Helper for TestConfigurationTests that wraps XCTestConfiguration interactions.
/// This is needed because XCTestPrivate cannot be imported from Swift due to module
/// conflicts with the system XCTest framework. Property access uses KVC since the
/// private class cannot declare conformance to any Swift-defined protocol.
final class TestConfigurationTestHelper {

  static func createTestConfigurationByWritingToFile(
    withSessionIdentifier sessionIdentifier: UUID,
    moduleName: String,
    testBundlePath: String,
    uiTesting: Bool,
    testsToRun: Set<String>?,
    testsToSkip: Set<String>?,
    targetApplicationPath: String?,
    targetApplicationBundleID: String?,
    testApplicationDependencies: [String: String]?,
    automationFrameworkPath: String?,
    reportActivities: Bool
  ) throws -> TestConfiguration {
    return try TestConfiguration(
      byWritingToFileWithSessionIdentifier: sessionIdentifier,
      moduleName: moduleName,
      testBundlePath: testBundlePath,
      uiTesting: uiTesting,
      testsToRun: testsToRun,
      testsToSkip: testsToSkip,
      targetApplicationPath: targetApplicationPath,
      targetApplicationBundleID: targetApplicationBundleID,
      testApplicationDependencies: testApplicationDependencies,
      automationFrameworkPath: automationFrameworkPath,
      reportActivities: reportActivities
    )
  }

  static func xcTestConfiguration(_ testConfiguration: TestConfiguration) -> Any? {
    testConfiguration.xcTestConfiguration
  }

  static func productModuleName(_ xcTestConfig: Any) -> String? {
    return (xcTestConfig as? NSObject)?.value(forKey: "productModuleName") as? String
  }

  static func testBundleURL(_ xcTestConfig: Any) -> URL? {
    return (xcTestConfig as? NSObject)?.value(forKey: "testBundleURL") as? URL
  }

  static func initialize(forUITesting xcTestConfig: Any) -> Bool {
    return (xcTestConfig as? NSObject)?.value(forKey: "initializeForUITesting") as? Bool ?? false
  }

  static func targetApplicationPath(_ xcTestConfig: Any) -> String? {
    return (xcTestConfig as? NSObject)?.value(forKey: "targetApplicationPath") as? String
  }

  static func targetApplicationBundleID(_ xcTestConfig: Any) -> String? {
    return (xcTestConfig as? NSObject)?.value(forKey: "targetApplicationBundleID") as? String
  }

  static func reportActivities(_ xcTestConfig: Any) -> Bool {
    return (xcTestConfig as? NSObject)?.value(forKey: "reportActivities") as? Bool ?? false
  }

  static func reportResults(toIDE xcTestConfig: Any) -> Bool {
    return (xcTestConfig as? NSObject)?.value(forKey: "reportResultsToIDE") as? Bool ?? false
  }

  static func ideCapabilitiesDictionary(_ xcTestConfig: Any) -> NSDictionary? {
    guard let obj = xcTestConfig as? NSObject else { return nil }
    guard let capabilities = obj.value(forKey: "IDECapabilities") as? NSObject else { return nil }
    return capabilities.value(forKey: "capabilitiesDictionary") as? NSDictionary
  }
}

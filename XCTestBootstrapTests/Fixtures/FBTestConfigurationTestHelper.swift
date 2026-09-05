/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import XCTestBootstrap

/// Helper for FBTestConfigurationTests that wraps XCTestConfiguration interactions.
/// This is needed because XCTestPrivate cannot be imported from Swift due to module
/// conflicts with the system XCTest framework. Property access uses KVC since the
/// private class cannot declare conformance to any Swift-defined protocol.
final class FBTestConfigurationTestHelper {

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
  ) throws -> FBTestConfiguration {
    return try FBTestConfiguration(
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

  /// `FBTestConfiguration.xcTestConfiguration` is typed `XCTestConfiguration *`, and that class is
  /// only forward declared in the header, so Swift cannot import the property at all. Read it
  /// through KVC, like every other accessor here.
  static func xcTestConfiguration(_ testConfiguration: FBTestConfiguration) -> Any? {
    return (testConfiguration as NSObject).value(forKey: "xcTestConfiguration")
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

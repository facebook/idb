/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import ObjectiveC
import XCTestBootstrap

/// Helper for FBTestConfigurationTests that wraps XCTestConfiguration interactions.
/// This is needed because XCTestPrivate cannot be imported from Swift due to module
/// conflicts with the system XCTest framework. Property access uses KVC since the
/// private class cannot declare conformance to any Swift-defined protocol.
final class FBTestConfigurationTestHelper {

  static func createXCTestConfiguration() -> Any {
    guard let cls = objc_lookUpClass("XCTestConfiguration") as? NSObject.Type else {
      preconditionFailure("XCTestConfiguration class not found in ObjC runtime")
    }
    return cls.init()
  }

  static func createTestConfiguration(
    withSessionIdentifier sessionIdentifier: UUID,
    moduleName: String,
    testBundlePath: String,
    path: String,
    uiTesting: Bool,
    xcTestConfiguration: Any
  ) -> FBTestConfiguration {
    // The init imported from ObjC expects XCTestConfiguration, which is unavailable in
    // Swift (forward-declared only). Call the ObjC factory method via the runtime instead.
    let selector = NSSelectorFromString(
      "configurationWithSessionIdentifier:moduleName:testBundlePath:path:uiTesting:xcTestConfiguration:"
    )
    typealias FactoryMethod =
      @convention(c) (
        AnyObject, Selector, NSUUID, NSString, NSString, NSString, Bool, AnyObject
      ) -> AnyObject
    let metaclass: AnyClass = object_getClass(FBTestConfiguration.self)!
    let imp = class_getMethodImplementation(metaclass, selector)!
    let method = unsafeBitCast(imp, to: FactoryMethod.self)
    let result = method(
      FBTestConfiguration.self,
      selector,
      sessionIdentifier as NSUUID,
      moduleName as NSString,
      testBundlePath as NSString,
      path as NSString,
      uiTesting,
      xcTestConfiguration as AnyObject
    )
    return result as! FBTestConfiguration
  }

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

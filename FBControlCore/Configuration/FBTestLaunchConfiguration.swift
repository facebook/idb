/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc(FBTestLaunchConfiguration)
public final class FBTestLaunchConfiguration: NSObject, NSCopying {

  @objc public let testBundle: FBBundleDescriptor
  @objc public let applicationLaunchConfiguration: FBApplicationLaunchConfiguration
  @objc public let testHostBundle: FBBundleDescriptor?
  @objc public let timeout: TimeInterval
  @objc public let shouldInitializeUITesting: Bool
  @objc public let shouldUseXcodebuild: Bool
  @objc public let testsToRun: Set<String>?
  @objc public let testsToSkip: Set<String>?
  @objc public let targetApplicationBundle: FBBundleDescriptor?
  @objc public let xcTestRunProperties: [String: Any]?
  @objc public let resultBundlePath: String?
  @objc public let reportActivities: Bool
  @objc public let coverageDirectoryPath: String?
  @objc public let shouldEnableContinuousCoverageCollection: Bool
  @objc public let logDirectoryPath: String?
  @objc public let reportResultBundle: Bool

  @objc
  public init(testBundle: FBBundleDescriptor, applicationLaunchConfiguration: FBApplicationLaunchConfiguration, testHostBundle: FBBundleDescriptor?, timeout: TimeInterval, initializeUITesting: Bool, useXcodebuild: Bool, testsToRun: Set<String>?, testsToSkip: Set<String>?, targetApplicationBundle: FBBundleDescriptor?, xcTestRunProperties: [String: Any]?, resultBundlePath: String?, reportActivities: Bool, coverageDirectoryPath: String?, enableContinuousCoverageCollection: Bool, logDirectoryPath: String?, reportResultBundle: Bool) {
    self.testBundle = testBundle
    self.applicationLaunchConfiguration = applicationLaunchConfiguration
    self.testHostBundle = testHostBundle
    self.timeout = timeout
    self.shouldInitializeUITesting = initializeUITesting
    self.shouldUseXcodebuild = useXcodebuild
    self.testsToRun = testsToRun
    self.testsToSkip = testsToSkip
    self.targetApplicationBundle = targetApplicationBundle
    self.xcTestRunProperties = xcTestRunProperties
    self.resultBundlePath = resultBundlePath
    self.reportActivities = reportActivities
    self.coverageDirectoryPath = coverageDirectoryPath
    self.shouldEnableContinuousCoverageCollection = enableContinuousCoverageCollection
    self.logDirectoryPath = logDirectoryPath
    self.reportResultBundle = reportResultBundle
    super.init()
  }

  // MARK: NSCopying

  public func copy(with zone: NSZone? = nil) -> Any {
    return self
  }

  // MARK: NSObject

  public override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? FBTestLaunchConfiguration else { return false }
    return testBundle == other.testBundle
      && applicationLaunchConfiguration == other.applicationLaunchConfiguration
      && testHostBundle == other.testHostBundle
      && targetApplicationBundle == other.targetApplicationBundle
      && testsToRun == other.testsToRun
      && testsToSkip == other.testsToSkip
      && timeout == other.timeout
      && shouldInitializeUITesting == other.shouldInitializeUITesting
      && shouldUseXcodebuild == other.shouldUseXcodebuild
      && (xcTestRunProperties as NSDictionary?) == (other.xcTestRunProperties as NSDictionary?)
      && resultBundlePath == other.resultBundlePath
      && coverageDirectoryPath == other.coverageDirectoryPath
      && shouldEnableContinuousCoverageCollection == other.shouldEnableContinuousCoverageCollection
      && logDirectoryPath == other.logDirectoryPath
      && reportResultBundle == other.reportResultBundle
  }

  public override var hash: Int {
    var h = testBundle.hash
    h ^= applicationLaunchConfiguration.hash
    h ^= testHostBundle?.hash ?? 0
    h ^= Int(timeout)
    h ^= shouldInitializeUITesting ? 1 : 0
    h ^= shouldUseXcodebuild ? 1 : 0
    h ^= (testsToRun as NSSet?)?.hash ?? 0
    h ^= (testsToSkip as NSSet?)?.hash ?? 0
    h ^= targetApplicationBundle?.hash ?? 0
    h ^= (xcTestRunProperties as NSDictionary?)?.hash ?? 0
    h ^= resultBundlePath?.hash ?? 0
    h ^= coverageDirectoryPath?.hash ?? 0
    h ^= shouldEnableContinuousCoverageCollection ? 1 : 0
    h ^= logDirectoryPath?.hash ?? 0
    return h
  }

  public override var description: String {
    return "FBTestLaunchConfiguration TestBundle \(testBundle) | AppConfig \(applicationLaunchConfiguration) | HostBundle \(testHostBundle.map(String.init(describing:)) ?? "(nil)") | UITesting \(shouldInitializeUITesting ? 1 : 0) | UseXcodebuild \(shouldUseXcodebuild ? 1 : 0) | TestsToRun \(testsToRun.map(String.init(describing:)) ?? "(nil)") | TestsToSkip \(testsToSkip.map(String.init(describing:)) ?? "(nil)") | Target application bundle \(targetApplicationBundle.map(String.init(describing:)) ?? "(nil)") xcTestRunProperties \(xcTestRunProperties.map(String.init(describing:)) ?? "(nil)") | ResultBundlePath \(resultBundlePath ?? "(nil)") | CoverageDirPath \(coverageDirectoryPath ?? "(nil)") | EnableContinuousCoverageCollection \(shouldEnableContinuousCoverageCollection ? 1 : 0) | LogDirectoryPath \(logDirectoryPath ?? "(nil)") | ReportResultBundle \(reportResultBundle ? 1 : 0)"
  }
}

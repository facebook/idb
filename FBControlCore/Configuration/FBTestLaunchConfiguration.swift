/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public struct FBTestLaunchConfiguration {

  public let testBundle: FBBundleDescriptor
  public let applicationLaunchConfiguration: FBApplicationLaunchConfiguration
  public let testHostBundle: FBBundleDescriptor?
  public let timeout: TimeInterval
  public let shouldInitializeUITesting: Bool
  public let shouldUseXcodebuild: Bool
  public let testsToRun: Set<String>?
  public let testsToSkip: Set<String>?
  public let targetApplicationBundle: FBBundleDescriptor?
  public let xcTestRunProperties: [String: Any]?
  public let resultBundlePath: String?
  public let reportActivities: Bool
  public let coverageDirectoryPath: String?
  public let shouldEnableContinuousCoverageCollection: Bool
  public let logDirectoryPath: String?
  public let reportResultBundle: Bool

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
  }
}

// MARK: - CustomStringConvertible

extension FBTestLaunchConfiguration: CustomStringConvertible {

  public var description: String {
    "FBTestLaunchConfiguration TestBundle \(testBundle) | AppConfig \(applicationLaunchConfiguration) | HostBundle \(testHostBundle.map(String.init(describing:)) ?? "(nil)") | UITesting \(shouldInitializeUITesting ? 1 : 0) | UseXcodebuild \(shouldUseXcodebuild ? 1 : 0) | TestsToRun \(testsToRun.map(String.init(describing:)) ?? "(nil)") | TestsToSkip \(testsToSkip.map(String.init(describing:)) ?? "(nil)") | Target application bundle \(targetApplicationBundle.map(String.init(describing:)) ?? "(nil)") xcTestRunProperties \(xcTestRunProperties.map(String.init(describing:)) ?? "(nil)") | ResultBundlePath \(resultBundlePath ?? "(nil)") | CoverageDirPath \(coverageDirectoryPath ?? "(nil)") | EnableContinuousCoverageCollection \(shouldEnableContinuousCoverageCollection ? 1 : 0) | LogDirectoryPath \(logDirectoryPath ?? "(nil)") | ReportResultBundle \(reportResultBundle ? 1 : 0)"
  }
}

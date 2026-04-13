/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Commands related to XCTest Execution.
/// FBXCTestReporter is defined in XCTestBootstrap -- reporter is typed as AnyObject to avoid circular module dependency.
@objc public protocol FBXCTestCommands: NSObjectProtocol, FBiOSTargetCommand {
  /// Bootstraps a test run using a Test Launch Configuration.
  @objc(runTestWithLaunchConfiguration:reporter:logger:)
  func runTest(withLaunchConfiguration testLaunchConfiguration: FBTestLaunchConfiguration, reporter: AnyObject, logger: FBControlCoreLogger) -> FBFuture<NSNull>
}

/// Extended commands supported on some platforms.
@objc public protocol FBXCTestExtendedCommands: FBXCTestCommands {
  /// Lists the testables for a provided test bundle.
  @objc(listTestsForBundleAtPath:timeout:withAppAtPath:)
  func listTests(forBundleAtPath bundlePath: String, timeout: TimeInterval, withAppAtPath appPath: String?) -> FBFuture<NSArray>

  /// Returns the platform specific shims.
  func extendedTestShim() -> FBFuture<NSString>

  /// Starts 'testmanagerd' connection and creates socket to it.
  func transportForTestManagerService() -> FBFutureContext<NSNumber>

  /// The Path to the xctest executable.
  var xctestPath: String { get }
}

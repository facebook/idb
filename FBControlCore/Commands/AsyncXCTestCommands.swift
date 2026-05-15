/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Swift-native async/await counterpart of `FBXCTestCommands`.
/// `reporter` is typed as `AnyObject` to avoid a circular module dependency on `XCTestBootstrap`.
public protocol AsyncXCTestCommands: AnyObject {

  func runTest(
    launchConfiguration: FBTestLaunchConfiguration,
    reporter: AnyObject,
    logger: any FBControlCoreLogger
  ) async throws
}

/// Swift-native async/await counterpart of `FBXCTestExtendedCommands`.
public protocol AsyncXCTestExtendedCommands: AsyncXCTestCommands {

  func listTests(
    forBundleAtPath bundlePath: String,
    timeout: TimeInterval,
    withAppAtPath appPath: String?
  ) async throws -> [String]

  func extendedTestShim() async throws -> String

  func withTransportForTestManagerService<R>(
    body: (NSNumber) async throws -> R
  ) async throws -> R

  var xctestPath: String { get }
}

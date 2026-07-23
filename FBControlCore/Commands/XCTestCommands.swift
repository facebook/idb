/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// `reporter` is typed as `AnyObject` to avoid a circular module dependency on `XCTestBootstrap`.
public protocol XCTestCommands: AnyObject {

  func runTest(
    launchConfiguration: FBTestLaunchConfiguration,
    reporter: AnyObject,
    logger: any FBControlCoreLogger
  ) async throws
}

public protocol XCTestExtendedCommands: XCTestCommands {

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

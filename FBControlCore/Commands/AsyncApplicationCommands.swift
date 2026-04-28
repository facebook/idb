/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Swift-native async/await counterpart of `FBApplicationCommands`.
/// Replaces `FBFuture`-returning methods with `async throws` ones and uses
/// Swift-native types in place of NSArray/NSDictionary/NSNumber/NSNull.
public protocol AsyncApplicationCommands: AnyObject {

  func installApplication(atPath path: String) async throws -> FBInstalledApplication

  func uninstallApplication(bundleID: String) async throws

  func launchApplication(_ configuration: FBApplicationLaunchConfiguration) async throws -> FBLaunchedApplication

  func killApplication(bundleID: String) async throws

  func installedApplications() async throws -> [FBInstalledApplication]

  func installedApplication(bundleID: String) async throws -> FBInstalledApplication

  func runningApplications() async throws -> [String: pid_t]

  func processID(forBundleID bundleID: String) async throws -> pid_t
}

/// Default bridge implementation for any class that already conforms to the
/// legacy `FBApplicationCommands` protocol. Delegates each async method to the
/// FBFuture-returning counterpart via `bridgeFBFuture`.
extension AsyncApplicationCommands where Self: FBApplicationCommands {

  public func installApplication(atPath path: String) async throws -> FBInstalledApplication {
    try await bridgeFBFuture(self.installApplication(withPath: path))
  }

  public func uninstallApplication(bundleID: String) async throws {
    try await bridgeFBFutureVoid(self.uninstallApplication(withBundleID: bundleID))
  }

  public func launchApplication(_ configuration: FBApplicationLaunchConfiguration) async throws -> FBLaunchedApplication {
    try await bridgeFBFuture(self.launchApplication(configuration))
  }

  public func killApplication(bundleID: String) async throws {
    try await bridgeFBFutureVoid(self.killApplication(withBundleID: bundleID))
  }

  public func installedApplications() async throws -> [FBInstalledApplication] {
    try await bridgeFBFutureArray(self.installedApplications())
  }

  public func installedApplication(bundleID: String) async throws -> FBInstalledApplication {
    try await bridgeFBFuture(self.installedApplication(withBundleID: bundleID))
  }

  public func runningApplications() async throws -> [String: pid_t] {
    let dict: [String: NSNumber] = try await bridgeFBFutureDictionary(self.runningApplications())
    return dict.mapValues { $0.int32Value }
  }

  public func processID(forBundleID bundleID: String) async throws -> pid_t {
    let n = try await bridgeFBFuture(self.processID(withBundleID: bundleID))
    return n.int32Value
  }
}

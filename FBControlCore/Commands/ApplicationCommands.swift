/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public protocol ApplicationLaunching: AnyObject {

  func launchApplication(_ configuration: FBApplicationLaunchConfiguration) async throws -> FBLaunchedApplication
}

public protocol ApplicationCommands: ApplicationLaunching {

  func installApplication(atPath path: String) async throws -> FBInstalledApplication

  func uninstallApplication(bundleID: String) async throws

  func killApplication(bundleID: String) async throws

  func installedApplications() async throws -> [FBInstalledApplication]

  func installedApplication(bundleID: String) async throws -> FBInstalledApplication

  func runningApplications() async throws -> [String: pid_t]

  func processID(forBundleID bundleID: String) async throws -> pid_t
}

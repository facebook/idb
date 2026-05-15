/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc public protocol FBApplicationCommands: NSObjectProtocol, FBiOSTargetCommand {

  @objc(installApplicationWithPath:)
  func installApplication(withPath path: String) -> FBFuture<FBInstalledApplication>

  @objc(uninstallApplicationWithBundleID:)
  func uninstallApplication(withBundleID bundleID: String) -> FBFuture<NSNull>

  @objc(launchApplication:)
  func launchApplication(_ configuration: FBApplicationLaunchConfiguration) -> FBFuture<FBLaunchedApplication>

  @objc(killApplicationWithBundleID:)
  func killApplication(withBundleID bundleID: String) -> FBFuture<NSNull>

  @objc func installedApplications() -> FBFuture<NSArray>

  @objc(installedApplicationWithBundleID:)
  func installedApplication(withBundleID bundleID: String) -> FBFuture<FBInstalledApplication>

  @objc(processIDWithBundleID:)
  func processID(withBundleID bundleID: String) -> FBFuture<NSNumber>
}

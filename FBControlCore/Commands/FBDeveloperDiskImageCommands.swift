/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc public protocol FBDeveloperDiskImageCommands: NSObjectProtocol, FBiOSTargetCommand {

  @objc func mountedDiskImages() -> FBFuture<NSArray>

  @objc(mountDiskImage:)
  func mountDiskImage(_ diskImage: FBDeveloperDiskImage) -> FBFuture<FBDeveloperDiskImage>

  @objc(unmountDiskImage:)
  func unmountDiskImage(_ diskImage: FBDeveloperDiskImage) -> FBFuture<NSNull>

  @objc func mountableDiskImages() -> [FBDeveloperDiskImage]

  @objc func ensureDeveloperDiskImageIsMounted() -> FBFuture<FBDeveloperDiskImage>
}

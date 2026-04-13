/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc public protocol FBFileCommands: NSObjectProtocol, FBiOSTargetCommand {

  @objc(fileCommandsForContainerApplication:)
  func fileCommandsForContainerApplication(_ bundleID: String) -> FBFutureContext<FBFileContainerProtocol>

  @objc func fileCommandsForAuxillary() -> FBFutureContext<FBFileContainerProtocol>

  @objc func fileCommandsForApplicationContainers() -> FBFutureContext<FBFileContainerProtocol>

  @objc func fileCommandsForGroupContainers() -> FBFutureContext<FBFileContainerProtocol>

  @objc func fileCommandsForRootFilesystem() -> FBFutureContext<FBFileContainerProtocol>

  @objc func fileCommandsForMediaDirectory() -> FBFutureContext<FBFileContainerProtocol>

  @objc func fileCommandsForProvisioningProfiles() -> FBFutureContext<FBFileContainerProtocol>

  @objc func fileCommandsForMDMProfiles() -> FBFutureContext<FBFileContainerProtocol>

  @objc func fileCommandsForSpringboardIconLayout() -> FBFutureContext<FBFileContainerProtocol>

  @objc func fileCommandsForWallpaper() -> FBFutureContext<FBFileContainerProtocol>

  @objc func fileCommandsForDiskImages() -> FBFutureContext<FBFileContainerProtocol>

  @objc func fileCommandsForSymbols() -> FBFutureContext<FBFileContainerProtocol>
}

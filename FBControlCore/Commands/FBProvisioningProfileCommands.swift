/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc public protocol FBProvisioningProfileCommands: NSObjectProtocol, FBiOSTargetCommand {

  @objc func allProvisioningProfiles() -> FBFuture<NSArray>

  @objc(removeProvisioningProfile:)
  func removeProvisioningProfile(_ uuid: String) -> FBFuture<NSDictionary>

  @objc(installProvisioningProfile:)
  func installProvisioningProfile(_ profileData: Data) -> FBFuture<NSDictionary>
}

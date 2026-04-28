/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Swift-native async/await counterpart of `FBProvisioningProfileCommands`.
public protocol AsyncProvisioningProfileCommands: AnyObject {

  func allProvisioningProfiles() async throws -> [[String: Any]]

  func removeProvisioningProfile(uuid: String) async throws -> [String: Any]

  func installProvisioningProfile(_ profileData: Data) async throws -> [String: Any]
}

/// Default bridge implementation against the legacy `FBProvisioningProfileCommands`
/// protocol.
extension AsyncProvisioningProfileCommands where Self: FBProvisioningProfileCommands {

  public func allProvisioningProfiles() async throws -> [[String: Any]] {
    try await bridgeFBFutureArray(self.allProvisioningProfiles())
  }

  public func removeProvisioningProfile(uuid: String) async throws -> [String: Any] {
    try await bridgeFBFutureDictionary(self.removeProvisioningProfile(uuid))
  }

  public func installProvisioningProfile(_ profileData: Data) async throws -> [String: Any] {
    try await bridgeFBFutureDictionary(self.installProvisioningProfile(profileData))
  }
}

/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public protocol ProvisioningProfileCommands: AnyObject {

  func all() async throws -> [[String: Any]]

  func remove(uuid: String) async throws -> [String: Any]

  func install(_ profileData: Data) async throws -> [String: Any]
}

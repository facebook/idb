/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc public protocol FBDeviceActivationCommandsProtocol: NSObjectProtocol {

  @objc func activate() -> FBFuture<NSNull>
}

// MARK: - FBDevice+FBDeviceActivationCommandsProtocol

extension FBDevice: FBDeviceActivationCommandsProtocol {

  @objc public func activate() -> FBFuture<NSNull> {
    do {
      return try activationCommands().activate()
    } catch {
      return FBFuture(error: error)
    }
  }
}

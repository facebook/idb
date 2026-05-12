/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc public protocol FBDeviceRecoveryCommandsProtocol: NSObjectProtocol {

  @objc func enterRecovery() -> FBFuture<NSNull>

  @objc func exitRecovery() -> FBFuture<NSNull>
}

// MARK: - FBDevice+FBDeviceRecoveryCommandsProtocol

extension FBDevice: FBDeviceRecoveryCommandsProtocol {

  @objc public func enterRecovery() -> FBFuture<NSNull> {
    do {
      return try recoveryCommands().enterRecovery()
    } catch {
      return FBFuture(error: error)
    }
  }

  @objc public func exitRecovery() -> FBFuture<NSNull> {
    do {
      return try recoveryCommands().exitRecovery()
    } catch {
      return FBFuture(error: error)
    }
  }
}

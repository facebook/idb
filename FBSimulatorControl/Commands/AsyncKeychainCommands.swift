/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// Swift-native async/await counterpart of `FBSimulatorKeychainCommandsProtocol`.
public protocol AsyncKeychainCommands: AnyObject {

  func clearKeychain() async throws
}

/// Default bridge implementation against the legacy
/// `FBSimulatorKeychainCommandsProtocol`.
extension AsyncKeychainCommands where Self: FBSimulatorKeychainCommandsProtocol {

  public func clearKeychain() async throws {
    try await bridgeFBFutureVoid(self.clearKeychain())
  }
}

/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Swift-native async/await counterpart of `FBPowerCommands`.
public protocol AsyncPowerCommands: AnyObject {

  func shutdown() async throws

  func reboot() async throws
}

/// Default bridge implementation against the legacy `FBPowerCommands` protocol.
extension AsyncPowerCommands where Self: FBPowerCommands {

  public func shutdown() async throws {
    try await bridgeFBFutureVoid(self.shutdown())
  }

  public func reboot() async throws {
    try await bridgeFBFutureVoid(self.reboot())
  }
}

/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// Swift-native async/await counterpart of the simulator-specific members of
/// `FBSimulatorLifecycleCommandsProtocol`.
public protocol AsyncSimulatorLifecycleCommands: AnyObject {

  func focus() async throws

  func open(_ url: URL) async throws

  func connectToHID() async throws -> FBSimulatorHID
}

/// Default bridge implementation against the legacy
/// `FBSimulatorLifecycleCommandsProtocol`.
extension AsyncSimulatorLifecycleCommands where Self: FBSimulatorLifecycleCommandsProtocol {

  public func focus() async throws {
    try await bridgeFBFutureVoid(self.focus())
  }

  public func open(_ url: URL) async throws {
    try await bridgeFBFutureVoid(self.open(url))
  }

  public func connectToHID() async throws -> FBSimulatorHID {
    return try await bridgeFBFuture(self.connectToHID())
  }
}

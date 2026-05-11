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

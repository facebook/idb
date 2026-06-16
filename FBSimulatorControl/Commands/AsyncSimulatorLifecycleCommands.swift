/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

public protocol AsyncSimulatorLifecycleCommands: AnyObject {

  func boot(_ configuration: FBSimulatorBootConfiguration) async throws

  func focus() async throws

  func disconnect(withTimeout timeout: TimeInterval, logger: (any FBControlCoreLogger)?) async throws

  func connectToFramebuffer() async throws -> FBFramebuffer

  func open(_ url: URL) async throws

  func connectToHID() async throws -> FBSimulatorHID
}

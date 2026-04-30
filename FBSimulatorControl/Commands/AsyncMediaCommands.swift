/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// Swift-native async/await counterpart of `FBSimulatorMediaCommandsProtocol`.
public protocol AsyncMediaCommands: AnyObject {

  func addMedia(_ mediaFileURLs: [URL]) async throws
}

/// Default bridge implementation against the legacy
/// `FBSimulatorMediaCommandsProtocol`.
extension AsyncMediaCommands where Self: FBSimulatorMediaCommandsProtocol {

  public func addMedia(_ mediaFileURLs: [URL]) async throws {
    try await bridgeFBFutureVoid(self.addMedia(mediaFileURLs))
  }
}

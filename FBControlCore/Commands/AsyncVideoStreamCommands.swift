/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Swift-native async/await counterpart of `FBVideoStreamCommands`.
public protocol AsyncVideoStreamCommands: AnyObject {

  func createStream(configuration: FBVideoStreamConfiguration) async throws -> any FBVideoStream
}

/// Default bridge implementation against the legacy `FBVideoStreamCommands`
/// protocol.
extension AsyncVideoStreamCommands where Self: FBVideoStreamCommands {

  public func createStream(configuration: FBVideoStreamConfiguration) async throws -> any FBVideoStream {
    try await bridgeFBFuture(self.createStream(with: configuration))
  }
}

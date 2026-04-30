/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc public protocol FBVideoStreamCommands: NSObjectProtocol, FBiOSTargetCommand {

  @objc(createStreamWithConfiguration:)
  func createStream(with configuration: FBVideoStreamConfiguration) -> FBFuture<FBVideoStream>
}

public extension FBVideoStreamCommands {

  func createStreamAsync(with configuration: FBVideoStreamConfiguration) async throws -> any FBVideoStream {
    try await bridgeFBFuture(self.createStream(with: configuration))
  }
}

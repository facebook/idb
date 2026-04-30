/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc public protocol FBVideoRecordingCommands: NSObjectProtocol, FBiOSTargetCommand {

  @objc(startRecordingToFile:)
  func startRecording(toFile filePath: String) -> FBFuture<FBiOSTargetOperation>

  @objc func stopRecording() -> FBFuture<NSNull>
}

public extension FBVideoRecordingCommands {

  func startRecordingAsync(toFile filePath: String) async throws -> any FBiOSTargetOperation {
    try await bridgeFBFuture(self.startRecording(toFile: filePath))
  }

  func stopRecordingAsync() async throws {
    try await bridgeFBFutureVoid(self.stopRecording())
  }
}

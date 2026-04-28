/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Swift-native async/await counterpart of `FBVideoRecordingCommands`.
public protocol AsyncVideoRecordingCommands: AnyObject {

  func startRecording(toFile filePath: String) async throws -> any FBiOSTargetOperation

  func stopRecording() async throws
}

/// Default bridge implementation against the legacy `FBVideoRecordingCommands`
/// protocol.
extension AsyncVideoRecordingCommands where Self: FBVideoRecordingCommands {

  public func startRecording(toFile filePath: String) async throws -> any FBiOSTargetOperation {
    try await bridgeFBFuture(self.startRecording(toFile: filePath))
  }

  public func stopRecording() async throws {
    try await bridgeFBFutureVoid(self.stopRecording())
  }
}

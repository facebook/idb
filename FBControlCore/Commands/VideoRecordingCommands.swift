/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public protocol VideoRecordingCommands: AnyObject {

  func startRecording(toFile filePath: String) async throws

  /// Record using a caller-provided stream configuration (codec, frame rate, scale, rate control,
  /// key-frame rate). Mirrors `VideoStreamCommands.createStream(configuration:)`.
  func startRecording(toFile filePath: String, configuration: FBVideoStreamConfiguration) async throws

  func stopRecording() async throws
}

public extension VideoRecordingCommands {

  /// Default: ignore the configuration and fall back to the target's fixed recording path. This lets
  /// conformers that cannot honor a configuration (e.g. `FBDevice`, whose recording is a separate
  /// `AVCaptureSession` path) inherit it unchanged; `FBSimulator` overrides it to honor the config.
  func startRecording(toFile filePath: String, configuration: FBVideoStreamConfiguration) async throws {
    try await startRecording(toFile: filePath)
  }
}

/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A handle to a running video recording. It is returned already recording; call `stop()` to finalize
/// the file and obtain its URL.
public protocol FBVideoRecording {

  /// Stops the recording, finalizes the file, and returns its URL.
  func stop() async throws -> URL
}

public protocol VideoRecordingCommands: AnyObject {

  func startRecording(toFile filePath: String) async throws -> any FBVideoRecording

  /// Record using a caller-provided stream configuration (codec, frame rate, scale, rate control,
  /// key-frame rate). Mirrors `VideoStreamCommands.createStream(configuration:to:)`.
  func startRecording(toFile filePath: String, configuration: FBVideoStreamConfiguration) async throws -> any FBVideoRecording
}

public extension VideoRecordingCommands {

  /// Default: ignore the configuration and fall back to the target's fixed recording path. This lets
  /// conformers that cannot honor a configuration (e.g. `FBDevice`, whose recording is a separate
  /// `AVCaptureSession` path) inherit it unchanged; `FBSimulator` overrides it to honor the config.
  func startRecording(toFile filePath: String, configuration: FBVideoStreamConfiguration) async throws -> any FBVideoRecording {
    try await startRecording(toFile: filePath)
  }
}

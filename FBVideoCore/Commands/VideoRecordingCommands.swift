/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// A handle to a running video recording. It is returned already recording; call `stop()` to finalize
/// the file and obtain its URL.
public protocol VideoRecording {

  func stop() async throws -> URL
}

public protocol VideoRecordingCommands {

  func start(toFile filePath: String) async throws -> any VideoRecording

  /// Record using a caller-provided stream configuration (codec, frame rate, scale, rate control,
  /// key-frame rate). Mirrors `VideoStreamCommands.create(configuration:to:)`.
  func start(toFile filePath: String, configuration: VideoStreamConfiguration) async throws -> any VideoRecording

  /// Whether the overload above applies the configuration or discards it. A caller that was asked
  /// for a specific frame rate or output size can then refuse, rather than recording something else
  /// and reporting success.
  var honorsRecordingConfiguration: Bool { get }
}

public extension VideoRecordingCommands {

  /// Default ignores the configuration. A conformer that can honor it overrides both members.
  func start(toFile filePath: String, configuration: VideoStreamConfiguration) async throws -> any VideoRecording {
    try await start(toFile: filePath)
  }

  var honorsRecordingConfiguration: Bool { false }
}

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

  func stop() async throws -> URL
}

/// A closure-backed recording handle for command implementations that keep ownership of the
/// underlying recording operation.
public final class FBVideoRecordingHandle: FBVideoRecording {
  private let stopAction: () async throws -> URL

  public init(stop: @escaping () async throws -> URL) {
    self.stopAction = stop
  }

  public func stop() async throws -> URL {
    try await stopAction()
  }
}

public protocol VideoRecordingCommands: AnyObject {

  func startRecording(toFile filePath: String) async throws -> any FBVideoRecording

  /// Record using a caller-provided stream configuration (codec, frame rate, scale, rate control,
  /// key-frame rate). Mirrors `VideoStreamCommands.createStream(configuration:to:)`.
  func startRecording(toFile filePath: String, configuration: FBVideoStreamConfiguration) async throws -> any FBVideoRecording

  /// Whether the overload above applies the configuration or discards it. A caller that was asked
  /// for a specific frame rate or output size can then refuse, rather than recording something else
  /// and reporting success.
  var honorsRecordingConfiguration: Bool { get }
}

public extension VideoRecordingCommands {

  /// Default ignores the configuration. A conformer that can honor it overrides both members.
  func startRecording(toFile filePath: String, configuration: FBVideoStreamConfiguration) async throws -> any FBVideoRecording {
    try await startRecording(toFile: filePath)
  }

  var honorsRecordingConfiguration: Bool { false }
}

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

  /// Adds the audio in a WAV file to the stopped recording's file, as a track of its own. `hostTime`
  /// is when the WAV's first frame played, in `mach_absolute_time` ticks, and places the track on the
  /// recording's timeline. Audio from before the recording's first frame is cut.
  func addAudio(fromWAV path: String, startingAtHostTime hostTime: UInt64) async throws -> AudioTrackPlacement
}

/// Where an added audio track sits in a recording.
public struct AudioTrackPlacement: Sendable {
  /// Seconds from the recording's start to the WAV's first frame, negative when the audio began first
  /// and that much of it was cut.
  public let offset: Double
  /// Frames of the WAV in the track.
  public let frames: Int

  public init(offset: Double, frames: Int) {
    self.offset = offset
    self.frames = frames
  }
}

/// Why a recording could not take audio.
public enum VideoRecordingAudioError: Error, LocalizedError {
  case unsupported(String)

  public var errorDescription: String? {
    switch self {
    case let .unsupported(target):
      return "A recording of \(target) cannot take an audio track"
    }
  }
}

public extension VideoRecording {

  /// Default refuses: only a conformer that can mux audio into its file overrides it.
  func addAudio(fromWAV path: String, startingAtHostTime hostTime: UInt64) async throws -> AudioTrackPlacement {
    throw VideoRecordingAudioError.unsupported(String(describing: type(of: self)))
  }
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

  /// Whether a recording these commands start can take an audio track, so that a caller asked for
  /// audio can refuse before recording rather than after.
  var acceptsAudio: Bool { get }
}

public extension VideoRecordingCommands {

  /// Default ignores the configuration. A conformer that can honor it overrides both members.
  func start(toFile filePath: String, configuration: VideoStreamConfiguration) async throws -> any VideoRecording {
    try await start(toFile: filePath)
  }

  var honorsRecordingConfiguration: Bool { false }

  var acceptsAudio: Bool { false }
}

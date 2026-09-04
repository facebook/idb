/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import GRPC
import IDBGRPCSwift

/// Translates a `record` request to `FBVideoEncodeOptions` and echoes the resolved options back.
/// Rejects what the encoder cannot honor (a quality out of range, an enlargement, two rate controls).
enum RecordRequestTranslation {

  /// A recording is always H.264 in an mp4; the transport is irrelevant because encoded samples are
  /// muxed to a file rather than byte-framed.
  static let format = FBVideoStreamFormat.compressedVideo(withCodec: .h264, transport: .annexB)

  /// What `FBSimulatorVideoRecordingCommands` has always pinned, and so what an unset `fps` has to
  /// mean here. The stream's unset `fps` means the display's own rate instead.
  static let defaultFramesPerSecond = 30

  /// The options the request asked for, or nil when it set none, so a client that predates these fields
  /// records exactly as before. Zero is unset: a proto3 scalar cannot distinguish the two.
  static func encodeOptions(from start: Idb_RecordRequest.Start) throws -> FBVideoEncodeOptions? {
    for (name, value) in [
      ("scale_factor", start.scaleFactor), ("avg_bitrate", start.avgBitrate),
      ("key_frame_rate", start.keyFrameRate), ("compression_quality", start.compressionQuality),
    ] {
      // These are proto3 doubles, so a client can send NaN or ±Infinity. None is meaningful here, and
      // an unchecked NaN would slip past every `> 0` / `<= 1` guard below and read as unset, while an
      // Infinity would reach a trapping `Int(...)` conversion and crash the companion. Reject both up
      // front, before the range checks that assume a finite value.
      guard value.isFinite else {
        throw GRPCStatus(code: .invalidArgument, message: "record \(name) must be a finite number, got \(value)")
      }
      guard value >= 0 else {
        throw GRPCStatus(code: .invalidArgument, message: "record \(name) must not be negative, got \(value)")
      }
    }
    guard start.compressionQuality <= 1 else {
      throw GRPCStatus(
        code: .invalidArgument,
        message: "record compression_quality must be in [0, 1], got \(start.compressionQuality)")
    }
    guard start.scaleFactor <= 1 else {
      throw GRPCStatus(
        code: .invalidArgument,
        message: "record scale_factor must be in (0, 1]; a recording can be shrunk but not enlarged, got \(start.scaleFactor)")
    }
    guard start.avgBitrate == 0 || start.compressionQuality == 0 else {
      throw GRPCStatus(
        code: .invalidArgument,
        message: "record avg_bitrate and compression_quality are two ways to set the same rate control; set one")
    }

    guard
      start.fps > 0 || start.compressionQuality > 0 || start.scaleFactor > 0
        || start.avgBitrate > 0 || start.keyFrameRate > 0
    else { return nil }

    let rateControl: FBVideoStreamRateControl?
    if start.avgBitrate > 0 {
      // Finite by the check above, but a finite double can still exceed `Int`, and `Int(_:)` traps on
      // an out-of-range value. Reject it as invalid rather than let the conversion crash the companion.
      guard start.avgBitrate < Double(Int.max) else {
        throw GRPCStatus(
          code: .invalidArgument,
          message: "record avg_bitrate is too large, got \(start.avgBitrate)")
      }
      rateControl = .bitrate(Int(start.avgBitrate))
    } else if start.compressionQuality > 0 {
      rateControl = .quality(start.compressionQuality)
    } else {
      rateControl = nil
    }

    return FBVideoEncodeOptions(
      framesPerSecond: start.fps > 0 ? Int(start.fps) : defaultFramesPerSecond,
      rateControl: rateControl,
      scaleFactor: start.scaleFactor > 0 ? start.scaleFactor : nil,
      keyFrameRate: start.keyFrameRate > 0 ? start.keyFrameRate : nil)
  }

  static func configuration(for options: FBVideoEncodeOptions) -> FBVideoStreamConfiguration {
    FBVideoStreamConfiguration(format: format, encodeOptions: options)
  }

  /// A conformer that inherits the default `startRecording(toFile:configuration:)` discards the
  /// configuration and records at its own settings. Recording something other than what was asked
  /// for and reporting success is the one outcome the caller cannot detect, so refuse instead.
  static func requireHonoredConfiguration(_ commands: any VideoRecordingCommands, describing target: String) throws {
    guard commands.honorsRecordingConfiguration else {
      throw GRPCStatus(
        code: .unimplemented,
        message: "\(target) records with a fixed configuration, so it cannot apply encode options")
    }
  }

  /// Echoes the resolved options (defaults filled in). No scaling reports as 1. Rate control is reported
  /// in the field the request chose; an automatic rate leaves both 0. A reported quality means the encoder
  /// was configured with it, not that H.264 acts on it.
  static func appliedResponse(_ options: FBVideoEncodeOptions) -> Idb_RecordResponse {
    Idb_RecordResponse.with {
      $0.output = .applied(
        .with {
          $0.fps = UInt64(options.framesPerSecond ?? defaultFramesPerSecond)
          $0.scaleFactor = options.scaleFactor ?? 1
          $0.keyFrameRate = options.keyFrameRate
          switch options.rateControl {
          case let .bitrate(bitrate):
            $0.avgBitrate = Double(bitrate)
          case let .quality(quality):
            $0.compressionQuality = quality
          case .automatic:
            break
          }
        })
    }
  }
}

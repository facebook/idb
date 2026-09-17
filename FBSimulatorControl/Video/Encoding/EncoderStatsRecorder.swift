/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreMedia
import FBControlCore
import Foundation
import os

/// Stats tracked by the video encoder (VideoToolbox).
/// Zeroed if the stream uses a non-encoded format (e.g. bitmap/BGRA).
public struct VideoEncoderStats: Sendable {
  public var callbackCount: UInt = 0
  public var writeCount: UInt = 0
  public var dropCount: UInt = 0
  var writeFailureCount: UInt = 0
  public var encodeErrorCount: UInt = 0
  public var tornFrameCount: UInt = 0
  public var totalEncodedBytes: UInt = 0
  var totalEncodeSubmitSeconds: CFTimeInterval = 0

  public init() {}
}

/// Accounts for what the encoder does with each frame: the running `VideoEncoderStats`, the
/// warmup and starvation diagnostics, and a stats line every `logInterval` seconds.
///
/// Every mutable field lives under one `OSAllocatedUnfairLock`, so the recorder is `Sendable` as it stands: the
/// VideoToolbox output handler records outcomes, the encode submission records its timing, and the
/// owning actor reads snapshots, from whatever threads they run on.
final class EncoderStatsRecorder: Sendable {

  /// What became of one frame the encoder was given.
  enum Outcome {
    /// The encoded sample reached the consumer, carrying this many bytes.
    case written(encodedBytes: Int)
    /// VideoToolbox dropped the frame (rate control had no budget for it).
    case dropped
    /// The sample was produced but the consumer refused it.
    case writeFailed
    /// VideoToolbox reported an error for the frame.
    case encodeError(OSStatus)
  }

  private struct State {
    var stats = VideoEncoderStats()
    var lastLoggedStats = VideoEncoderStats()
    var consecutiveNotReadyFrameCount: UInt = 0
    var warmupComplete = false
    var starvationWarningLogged = false
    var statsTimer: PeriodicStatsTimer
  }

  /// Frames the encoder may take to produce its first output before that is worth a warning.
  static let warmupWindowFrames: UInt = 20
  /// Consecutive unproduced frames after warmup that indicate the bitrate is too low.
  static let starvationThreshold: UInt = 10

  private let logger: any ControlCoreLogger
  private let state: OSAllocatedUnfairLock<State>

  init(logger: any ControlCoreLogger, logInterval: CFTimeInterval = 5.0) {
    self.logger = logger
    self.state = OSAllocatedUnfairLock(initialState: State(statsTimer: PeriodicStatsTimer(interval: logInterval)))
  }

  /// The stats so far.
  var snapshot: VideoEncoderStats {
    state.withLock { $0.stats }
  }

  var warmupComplete: Bool {
    state.withLock { $0.warmupComplete }
  }

  var consecutiveNotReadyFrameCount: UInt {
    state.withLock { $0.consecutiveNotReadyFrameCount }
  }

  var starvationWarningLogged: Bool {
    state.withLock { $0.starvationWarningLogged }
  }

  /// Test seam: move the periodic log's last-fired time back so the next `record` logs.
  func backdateStatsTimerForTesting(by seconds: CFTimeInterval) {
    state.withLock { $0.statsTimer.backdateForTesting(by: seconds) }
  }

  /// A log line produced under the lock and emitted after it is released.
  private enum LogLine {
    case info(String)
    case warning(String)
  }

  /// One encoder callback's outcome. Counts it, tracks warmup and starvation, and logs the periodic
  /// stats line when the interval has elapsed. Logging happens outside the lock.
  func record(_ outcome: Outcome) {
    let lines = state.withLock { state -> [LogLine] in
      var messages: [LogLine] = []
      if !state.statsTimer.hasStarted {
        _ = state.statsTimer.tick()
        messages.append(.info("First encode callback received"))
      }

      state.stats.callbackCount += 1
      switch outcome {
      case let .encodeError(status):
        state.stats.encodeErrorCount += 1
        messages.append(.warning("VideoToolbox encode error: OSStatus \(status)"))
      case .dropped:
        state.stats.dropCount += 1
        messages += Self.recordFrameNotProduced(&state)
      case .writeFailed:
        state.stats.writeFailureCount += 1
        messages += Self.recordFrameNotProduced(&state)
      case let .written(encodedBytes):
        state.stats.writeCount += 1
        state.stats.totalEncodedBytes += UInt(encodedBytes)
        messages += Self.recordFrameProduced(&state)
      }

      messages += Self.periodicStatsIfDue(&state)
      return messages
    }
    for line in lines {
      switch line {
      case let .info(text):
        logger.info().log(text)
      case let .warning(text):
        logger.log(text)
      }
    }
  }

  /// The wall time an encode submission took, converter included.
  func recordEncodeSubmission(seconds: CFTimeInterval) {
    state.withLock { $0.stats.totalEncodeSubmitSeconds += seconds }
  }

  /// The source surface changed while a frame was being read.
  func recordTornFrame() {
    state.withLock { $0.stats.tornFrameCount += 1 }
  }

  // MARK: - Warmup and starvation

  private static func recordFrameNotProduced(_ state: inout State) -> [LogLine] {
    state.consecutiveNotReadyFrameCount += 1
    let consecutiveFailures = state.consecutiveNotReadyFrameCount
    if !state.warmupComplete {
      if consecutiveFailures == warmupWindowFrames {
        state.starvationWarningLogged = true
        return [.warning("Encoder has not produced a frame after \(consecutiveFailures) attempts — bitrate may be too low for this resolution")]
      }
    } else if consecutiveFailures == starvationThreshold && !state.starvationWarningLogged {
      state.starvationWarningLogged = true
      return [.warning("Encoder starvation: \(consecutiveFailures) consecutive frames not ready after warmup — bitrate is likely too low")]
    }
    return []
  }

  private static func recordFrameProduced(_ state: inout State) -> [LogLine] {
    let failuresBefore = state.consecutiveNotReadyFrameCount
    state.consecutiveNotReadyFrameCount = 0
    state.starvationWarningLogged = false
    guard !state.warmupComplete else {
      return []
    }
    state.warmupComplete = true
    return failuresBefore > 0 ? [.warning("Encoder warmed up after \(failuresBefore) skipped frames")] : []
  }

  // MARK: - Periodic log

  private static func periodicStatsIfDue(_ state: inout State) -> [LogLine] {
    guard case let .elapsed(intervalDuration, totalElapsed) = state.statsTimer.tick() else {
      return []
    }
    let current = state.stats
    let last = state.lastLoggedStats
    state.lastLoggedStats = current

    let intervalCallbacks = current.callbackCount - last.callbackCount
    let intervalEncodedBytes = current.totalEncodedBytes - last.totalEncodedBytes
    let intervalEncodeSubmitSeconds = current.totalEncodeSubmitSeconds - last.totalEncodeSubmitSeconds

    let totalFps = totalElapsed > 0 ? Double(current.callbackCount) / totalElapsed : 0
    let intervalFps = intervalDuration > 0 ? Double(intervalCallbacks) / intervalDuration : 0
    let intervalBitrateKbps = intervalDuration > 0 ? Double(intervalEncodedBytes) * 8.0 / 1000.0 / intervalDuration : 0
    let totalBitrateKbps = totalElapsed > 0 ? Double(current.totalEncodedBytes) * 8.0 / 1000.0 / totalElapsed : 0
    let intervalAvgEncodeMs = intervalCallbacks > 0 ? (intervalEncodeSubmitSeconds / Double(intervalCallbacks)) * 1000.0 : 0
    let totalAvgEncodeMs = current.callbackCount > 0 ? (current.totalEncodeSubmitSeconds / Double(current.callbackCount)) * 1000.0 : 0

    return [
      .info(
        String(
          format:
            "Video stats (interval): %lu callbacks in %.1fs (%.1f fps, %.0f kbps, %.2f ms/frame encode) — %lu written, %lu dropped, %lu write failures, %lu encode errors, %lu torn",
          intervalCallbacks, intervalDuration, intervalFps, intervalBitrateKbps, intervalAvgEncodeMs,
          current.writeCount - last.writeCount, current.dropCount - last.dropCount, current.writeFailureCount - last.writeFailureCount,
          current.encodeErrorCount - last.encodeErrorCount, current.tornFrameCount - last.tornFrameCount)),
      .info(
        String(
          format:
            "Video stats (total): %lu callbacks in %.1fs (%.1f fps, %.0f kbps, %.2f ms/frame encode) — %lu written, %lu dropped, %lu write failures, %lu encode errors, %lu torn",
          current.callbackCount, totalElapsed, totalFps, totalBitrateKbps, totalAvgEncodeMs,
          current.writeCount, current.dropCount, current.writeFailureCount, current.encodeErrorCount, current.tornFrameCount)),
    ]
  }
}

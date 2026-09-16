/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreMedia
import FBControlCore
import Foundation

/// Stats tracked by the video encoder (VideoToolbox).
/// Zeroed if the stream uses a non-encoded format (e.g. bitmap/BGRA).
public struct VideoEncoderStats: Sendable {
  public var callbackCount: UInt
  public var writeCount: UInt
  public var dropCount: UInt
  var writeFailureCount: UInt
  public var encodeErrorCount: UInt
  public var tornFrameCount: UInt
  public var totalEncodedBytes: UInt
  var totalEncodeSubmitSeconds: CFTimeInterval

  public init() {
    self.callbackCount = 0
    self.writeCount = 0
    self.dropCount = 0
    self.writeFailureCount = 0
    self.encodeErrorCount = 0
    self.tornFrameCount = 0
    self.totalEncodedBytes = 0
    self.totalEncodeSubmitSeconds = 0
  }

  public init(
    callbackCount: UInt,
    writeCount: UInt,
    dropCount: UInt,
    writeFailureCount: UInt,
    encodeErrorCount: UInt,
    tornFrameCount: UInt,
    totalEncodedBytes: UInt,
    totalEncodeSubmitSeconds: CFTimeInterval
  ) {
    self.callbackCount = callbackCount
    self.writeCount = writeCount
    self.dropCount = dropCount
    self.writeFailureCount = writeFailureCount
    self.encodeErrorCount = encodeErrorCount
    self.tornFrameCount = tornFrameCount
    self.totalEncodedBytes = totalEncodedBytes
    self.totalEncodeSubmitSeconds = totalEncodeSubmitSeconds
  }
}

/// Accounts for what the encoder does with each frame: the running `VideoEncoderStats`, the
/// warmup and starvation diagnostics, and a stats line every `logInterval` seconds.
///
/// @unchecked Sendable: `record(_:)` runs inside the VideoToolbox output handler, which a session
/// invokes serially, so the diagnostic state it owns (`warmupComplete`, the consecutive-failure count,
/// the log timer) is never touched concurrently. `stats` is also written from the encode submission
/// and read by `snapshot` from arbitrary isolation domains, so it alone is guarded by `lock`.
final class EncoderStatsRecorder: @unchecked Sendable {

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

  private let logger: any ControlCoreLogger
  private let lock = NSLock()
  private var stats = VideoEncoderStats()

  private var lastLoggedStats = VideoEncoderStats()
  private(set) var consecutiveNotReadyFrameCount: UInt = 0
  private(set) var warmupComplete = false
  private(set) var starvationWarningLogged = false
  var statsTimer: PeriodicStatsTimer

  /// Frames the encoder may take to produce its first output before that is worth a warning.
  static let warmupWindowFrames: UInt = 20
  /// Consecutive unproduced frames after warmup that indicate the bitrate is too low.
  static let starvationThreshold: UInt = 10

  init(logger: any ControlCoreLogger, logInterval: CFTimeInterval = 5.0) {
    self.logger = logger
    self.statsTimer = PeriodicStatsTimer(interval: logInterval)
  }

  /// The stats so far.
  var snapshot: VideoEncoderStats {
    lock.lock()
    defer { lock.unlock() }
    return stats
  }

  private func update(_ body: (inout VideoEncoderStats) -> Void) {
    lock.lock()
    defer { lock.unlock() }
    body(&stats)
  }

  /// One encoder callback's outcome. Counts it, tracks warmup and starvation, and logs the periodic
  /// stats line when the interval has elapsed.
  func record(_ outcome: Outcome) {
    if !statsTimer.hasStarted {
      _ = statsTimer.tick()
      logger.info().log("First encode callback received")
    }

    update { $0.callbackCount += 1 }
    switch outcome {
    case let .encodeError(status):
      update { $0.encodeErrorCount += 1 }
      logger.log("VideoToolbox encode error: OSStatus \(status)")
    case .dropped:
      update { $0.dropCount += 1 }
      recordFrameNotProduced()
    case .writeFailed:
      update { $0.writeFailureCount += 1 }
      recordFrameNotProduced()
    case let .written(encodedBytes):
      update {
        $0.writeCount += 1
        $0.totalEncodedBytes += UInt(encodedBytes)
      }
      recordFrameProduced()
    }

    logPeriodicStatsIfDue()
  }

  /// The wall time an encode submission took, converter included.
  func recordEncodeSubmission(seconds: CFTimeInterval) {
    update { $0.totalEncodeSubmitSeconds += seconds }
  }

  /// The source surface changed while a frame was being read.
  func recordTornFrame() {
    update { $0.tornFrameCount += 1 }
  }

  // MARK: - Warmup and starvation

  private func recordFrameNotProduced() {
    consecutiveNotReadyFrameCount += 1
    let consecutiveFailures = consecutiveNotReadyFrameCount
    if !warmupComplete {
      if consecutiveFailures == Self.warmupWindowFrames {
        logger.log("Encoder has not produced a frame after \(consecutiveFailures) attempts — bitrate may be too low for this resolution")
        starvationWarningLogged = true
      }
    } else if consecutiveFailures == Self.starvationThreshold && !starvationWarningLogged {
      logger.log("Encoder starvation: \(consecutiveFailures) consecutive frames not ready after warmup — bitrate is likely too low")
      starvationWarningLogged = true
    }
  }

  private func recordFrameProduced() {
    let failuresBefore = consecutiveNotReadyFrameCount
    consecutiveNotReadyFrameCount = 0
    starvationWarningLogged = false
    if !warmupComplete {
      warmupComplete = true
      if failuresBefore > 0 {
        logger.log("Encoder warmed up after \(failuresBefore) skipped frames")
      }
    }
  }

  // MARK: - Periodic log

  private func logPeriodicStatsIfDue() {
    guard case let .elapsed(intervalDuration, totalElapsed) = statsTimer.tick() else {
      return
    }
    let current = snapshot
    let last = lastLoggedStats
    lastLoggedStats = current

    let intervalCallbacks = current.callbackCount - last.callbackCount
    let intervalEncodedBytes = current.totalEncodedBytes - last.totalEncodedBytes
    let intervalEncodeSubmitSeconds = current.totalEncodeSubmitSeconds - last.totalEncodeSubmitSeconds

    let totalFps = totalElapsed > 0 ? Double(current.callbackCount) / totalElapsed : 0
    let intervalFps = intervalDuration > 0 ? Double(intervalCallbacks) / intervalDuration : 0
    let intervalBitrateKbps = intervalDuration > 0 ? Double(intervalEncodedBytes) * 8.0 / 1000.0 / intervalDuration : 0
    let totalBitrateKbps = totalElapsed > 0 ? Double(current.totalEncodedBytes) * 8.0 / 1000.0 / totalElapsed : 0
    let intervalAvgEncodeMs = intervalCallbacks > 0 ? (intervalEncodeSubmitSeconds / Double(intervalCallbacks)) * 1000.0 : 0
    let totalAvgEncodeMs = current.callbackCount > 0 ? (current.totalEncodeSubmitSeconds / Double(current.callbackCount)) * 1000.0 : 0

    logger.info().log(
      String(
        format:
          "Video stats (interval): %lu callbacks in %.1fs (%.1f fps, %.0f kbps, %.2f ms/frame encode) — %lu written, %lu dropped, %lu write failures, %lu encode errors, %lu torn",
        intervalCallbacks, intervalDuration, intervalFps, intervalBitrateKbps, intervalAvgEncodeMs,
        current.writeCount - last.writeCount, current.dropCount - last.dropCount, current.writeFailureCount - last.writeFailureCount,
        current.encodeErrorCount - last.encodeErrorCount, current.tornFrameCount - last.tornFrameCount))
    logger.info().log(
      String(
        format:
          "Video stats (total): %lu callbacks in %.1fs (%.1f fps, %.0f kbps, %.2f ms/frame encode) — %lu written, %lu dropped, %lu write failures, %lu encode errors, %lu torn",
        current.callbackCount, totalElapsed, totalFps, totalBitrateKbps, totalAvgEncodeMs,
        current.writeCount, current.dropCount, current.writeFailureCount, current.encodeErrorCount, current.tornFrameCount))
  }
}

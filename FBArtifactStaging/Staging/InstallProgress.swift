/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// The stages an application install passes through.
///
/// Not every install has every stage: one given a `.app` directory has only
/// `install`, and one given a local archive has no `download`.
public enum InstallStage: String, Sendable, Codable {
  case download
  case extract
  case install
}

/// Where within its stage an event sits.
public enum InstallPhase: String, Sendable, Codable {
  case started
  case progress
  case completed
}

/// How long an event's stage, and the install as a whole, have been running.
///
/// Both are reported because stages overlap: extraction consumes a download's
/// bytes as they arrive, so a stage's own elapsed time cannot be derived by
/// subtracting one total from another.
public struct InstallProgressTiming: Sendable {

  /// Since the stage this event belongs to began.
  public let elapsedMs: Int64

  /// Since the install began.
  public let totalElapsedMs: Int64

  public init(elapsedMs: Int64, totalElapsedMs: Int64) {
    self.elapsedMs = elapsedMs
    self.totalElapsedMs = totalElapsedMs
  }

  /// Measures the current time against the start of a stage and of the install.
  public static func measure(
    stageStart: Date, totalStart: Date, now: Date = Date()
  ) -> InstallProgressTiming {
    return InstallProgressTiming(
      elapsedMs: Int64(now.timeIntervalSince(stageStart) * 1000),
      totalElapsedMs: Int64(now.timeIntervalSince(totalStart) * 1000))
  }
}

/// Something an install has done, or has got partway through doing.
public enum InstallProgressEvent: Sendable {
  case downloadStarted(timing: InstallProgressTiming, url: URL)
  case downloadProgress(
    timing: InstallProgressTiming, bytesDownloaded: Int64, totalBytes: Int64?)
  case downloadCompleted(timing: InstallProgressTiming, totalBytes: Int64)
  case extractStarted(timing: InstallProgressTiming, destinationPath: String)
  case extractCompleted(timing: InstallProgressTiming, destinationPath: String)
  case installStarted(timing: InstallProgressTiming, artifactPath: String)
  /// `name` is what the installed artifact is known by on the target: an application's bundle identifier, or the file name of anything else.
  case installCompleted(timing: InstallProgressTiming, artifactPath: String, name: String)

  public var stage: InstallStage {
    switch self {
    case .downloadStarted, .downloadProgress, .downloadCompleted:
      return .download
    case .extractStarted, .extractCompleted:
      return .extract
    case .installStarted, .installCompleted:
      return .install
    }
  }

  public var phase: InstallPhase {
    switch self {
    case .downloadStarted, .extractStarted, .installStarted:
      return .started
    case .downloadProgress:
      return .progress
    case .downloadCompleted, .extractCompleted, .installCompleted:
      return .completed
    }
  }

  public var timing: InstallProgressTiming {
    switch self {
    case .downloadStarted(let timing, _):
      return timing
    case .downloadProgress(let timing, _, _):
      return timing
    case .downloadCompleted(let timing, _):
      return timing
    case .extractStarted(let timing, _):
      return timing
    case .extractCompleted(let timing, _):
      return timing
    case .installStarted(let timing, _):
      return timing
    case .installCompleted(let timing, _, _):
      return timing
    }
  }

  public var elapsedMs: Int64 { timing.elapsedMs }

  public var totalElapsedMs: Int64 { timing.totalElapsedMs }
}

/// A reportable download update, once the raw byte count has crossed a
/// threshold worth telling anyone about.
public struct DownloadProgressUpdate: Sendable {
  public let bytesDownloaded: Int64

  /// Absent when the server did not say how much to expect.
  public let totalBytes: Int64?

  public init(bytesDownloaded: Int64, totalBytes: Int64?) {
    self.bytesDownloaded = bytesDownloaded
    self.totalBytes = totalBytes
  }
}

/// Turns a stream of arbitrarily sized chunks into occasional updates.
///
/// Chunks arrive at network granularity -- often only kilobytes -- and reporting
/// each one would emit thousands of events for a single archive. An update is
/// produced once enough bytes have accumulated, or enough time has passed that a
/// slow transfer still looks alive.
public struct DownloadProgressState {

  /// Report after this many bytes, absent a caller saying otherwise.
  public static let defaultByteThreshold: Int64 = 10_000_000

  /// Report after this long, absent a caller saying otherwise.
  public static let defaultTimeThreshold: TimeInterval = 2.0

  public private(set) var downloadedBytes: Int64 = 0
  public private(set) var totalBytes: Int64?

  private var lastReportedBytes: Int64 = 0
  private var lastReportedAt: Date

  public init(startedAt: Date) {
    self.lastReportedAt = startedAt
  }

  /// Records what the server said to expect. A length of zero or less means it
  /// did not say, and is recorded as unknown rather than as a total.
  public mutating func observe(expectedContentLength: Int64) {
    totalBytes = expectedContentLength > 0 ? expectedContentLength : nil
  }

  /// Accumulates a chunk, returning an update only when one is due.
  ///
  /// Takes the size rather than the bytes, because it is called once per network
  /// chunk and never has any use for their contents.
  public mutating func track(
    byteCount: Int,
    now: Date = Date(),
    byteThreshold: Int64 = DownloadProgressState.defaultByteThreshold,
    timeThreshold: TimeInterval = DownloadProgressState.defaultTimeThreshold
  ) -> DownloadProgressUpdate? {
    downloadedBytes += Int64(byteCount)
    let bytesDue = downloadedBytes - lastReportedBytes >= byteThreshold
    let timeDue = now.timeIntervalSince(lastReportedAt) >= timeThreshold
    guard bytesDue || timeDue else {
      return nil
    }
    lastReportedBytes = downloadedBytes
    lastReportedAt = now
    return DownloadProgressUpdate(bytesDownloaded: downloadedBytes, totalBytes: totalBytes)
  }
}

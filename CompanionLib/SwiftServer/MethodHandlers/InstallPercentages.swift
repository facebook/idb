/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBArtifactStaging
import FBControlCore
import Foundation
import os

/// The whole percentages of a download an install has received, each reported once.
final class InstallPercentages: Sendable {

  let percentages: AsyncStream<Double>
  private let continuation: AsyncStream<Double>.Continuation
  private let reported = OSAllocatedUnfairLock<Int>(initialState: 0)

  /// Only a rise is reported, so at most 100 values are ever buffered.
  init() {
    (percentages, continuation) = AsyncStream.makeStream(of: Double.self, bufferingPolicy: .unbounded)
  }

  func observe(_ event: InstallProgressEvent) {
    guard let percent = Self.percent(of: event) else {
      return
    }
    reported.withLock { reported in
      guard percent > reported else {
        return
      }
      reported = percent
      continuation.yield(Double(percent))
    }
  }

  func finish() {
    continuation.finish()
  }

  /// A download of unknown length has no percentage.
  static func percent(of event: InstallProgressEvent) -> Int? {
    switch event {
    case .downloadProgress(_, let bytesDownloaded, let totalBytes?) where totalBytes > 0:
      return Int(min(max(bytesDownloaded, 0), totalBytes) * 100 / totalBytes)
    case .downloadProgress,
      .downloadStarted,
      .downloadCompleted,
      .extractStarted,
      .extractCompleted,
      .installStarted,
      .installCompleted:
      return nil
    }
  }
}

// MARK: - Reporting

extension InstallPercentages {

  /// Runs `install`, sending each percentage of its download as it arrives and all of them before returning.
  static func reporting<T>(
    to send: @escaping @Sendable (Double) async throws -> Void,
    _ install: (@escaping @Sendable (InstallProgressEvent) -> Void) async throws -> T
  ) async throws -> T {
    let percentages = InstallPercentages()
    async let sent: Void = {
      for await percent in percentages.percentages {
        try await send(percent)
      }
    }()
    let result: T
    do {
      result = try await install(percentages.observe)
    } catch {
      percentages.finish()
      try? await sent
      throw error
    }
    percentages.finish()
    try await sent
    return result
  }
}

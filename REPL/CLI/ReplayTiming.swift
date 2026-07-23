/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Schedules replayed runs to match the original session's timing (`--realtime`). Pure
/// and free of I/O apart from sleeping, so the offset math can be unit-tested directly.
enum ReplayTiming {

  /// The wall-clock offset (seconds from replay start) at which each run should begin,
  /// derived from the runs' recorded timestamps. The first run anchors at offset 0; each
  /// later offset is its timestamp minus the first run's, clamped to be non-negative and
  /// non-decreasing so a clock that went backwards between runs never schedules a run
  /// before its predecessor.
  ///
  /// The recorded timestamps are run *completion* times, so the schedule reproduces the
  /// original cadence closely but not exactly. Skipped compile failures leave no run of
  /// their own, but the gaps they occupied are still reflected because offsets are
  /// absolute from the start rather than accumulated deltas.
  static func offsets(forTimestamps timestamps: [Date]) -> [TimeInterval] {
    guard let first = timestamps.first else {
      return []
    }
    var offsets: [TimeInterval] = []
    var previous: TimeInterval = 0
    for timestamp in timestamps {
      let offset = max(previous, max(0, timestamp.timeIntervalSince(first)))
      offsets.append(offset)
      previous = offset
    }
    return offsets
  }

  /// Sleeps until `target`, or returns immediately if `target` is already in the past.
  /// Cancellation ends the wait silently.
  static func waitUntil(_ target: Date) async {
    let seconds = target.timeIntervalSinceNow
    guard seconds > 0 else {
      return
    }
    // Clamp to UInt64 range to avoid overflow on an absurd timestamp.
    let nanoseconds = min(seconds * 1_000_000_000, Double(UInt64.max))
    try? await Task.sleep(nanoseconds: UInt64(nanoseconds))
  }
}

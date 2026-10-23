/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// How a probed request ended.
package enum AccessibilityStallOutcome: String, Sendable {
  case answered
  case unanswered
  /// The read was cancelled while the request waited.
  case cancelled
}

/// One translator request that took long enough for the process it targeted to be probed, and what that
/// process and the host did meanwhile.
///
/// The target's counter changes and `hostBusyPercent` cover the wait from `baselineMilliseconds` to its end.
/// They are nil when there is no baseline (the request ended before one was read) and, for the counters, when
/// the process could not be read at both ends or was replaced by another with its pid in between.
package struct AccessibilityStallObservation: Sendable {
  package let requestKind: String
  package let pid: pid_t
  package let duration: CFAbsoluteTime
  package let outcome: AccessibilityStallOutcome
  /// When the baseline was read, from the start of the request.
  package let baselineMilliseconds: Int?
  /// CPU time the process used from the baseline to the end of the request.
  package let cpuMilliseconds: Int?
  package let contextSwitches: Int?
  package let syscalls: Int?
  let pageins: Int?
  /// At the end of the request.
  package let runningThreads: Int?
  let threads: Int?
  /// The process's BSD status at the end of the request: `runnable`, `sleeping`, `stopped`, …, or `unknown`
  /// when it could not be read.
  package let processStatus: String
  /// The host's one-minute load average at the end of the request.
  package let hostLoad: Double?
  /// The host's busy share of its CPU, from its ticks at the baseline and at the end of the request.
  package let hostBusyPercent: Int?
  /// The threads that used the most CPU from the baseline on, busiest first; empty when none used any, nil
  /// when the threads could not be listed at both ends.
  let busiestThreads: [AXThreadUse]?
  /// The process's oldest thread, which is its main thread.
  let mainThread: AXThreadUse?
  let footprintMegabytes: Int?
  let residentMegabytes: Int?
  let host: AXHostFacts
  let memory: AXMemoryState
  /// How long reading the baseline took.
  let probeMicroseconds: Int
  /// How long the probe held the request's thread: starting and stopping the watch, and reading the target and
  /// the host at the end. The request took `duration` plus this.
  package let probeInlineMicroseconds: Int
  /// Whether the process was read at the baseline. A request without a target, as for the frontmost
  /// application, is put down to the process its answer names, which could not be read beforehand.
  let probedBefore: Bool
  /// Whether the pid named a different process at the end of the request than at the baseline.
  let targetReplaced: Bool

  package var mainThreadCPUMilliseconds: Int? { mainThread?.cpuMilliseconds }
}

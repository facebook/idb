/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Foundation

/// Test double for the display reads. Only `interactionTarget()` is modelled, so routing built on it
/// runs the real logic. Each read takes the next scripted result; the last one repeats.
// SAFETY: The script and read count are guarded by the lock.
// patternlint-disable-next-line unchecked-sendable
final class DisplayCommandsDouble: DisplayCommands, @unchecked Sendable {
  let identities = DisplayIdentityCache()
  private let lock = NSLock()
  private var results: [Result<SimulatorDisplayTarget, any Error>]
  private var readCount = 0

  init(_ results: [Result<SimulatorDisplayTarget, any Error>]) {
    precondition(!results.isEmpty)
    self.results = results
  }

  convenience init(_ targets: SimulatorDisplayTarget...) {
    self.init(targets.map { .success($0) })
  }

  var reads: Int {
    lock.lock()
    defer { lock.unlock() }
    return readCount
  }

  func interactionTarget() async throws -> SimulatorDisplayTarget {
    lock.lock()
    defer { lock.unlock() }
    readCount += 1
    return try (results.count > 1 ? results.removeFirst() : results[0]).get()
  }
}

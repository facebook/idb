/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBArtifactStaging
@testable import FBControlCore
import Foundation
import Testing
import os

@Suite
struct ArchiveExtractorTests {

  /// More calls than the system runs at once on the global queues' constrained thread pool.
  private static let blockingCalls: Int = {
    var limit: Int32 = 0
    var size = MemoryLayout<Int32>.size
    sysctlbyname("kern.wq_max_constrained_threads", &limit, &size, nil, 0)
    return Int(limit) + 16
  }()

  @Test
  func offCooperativePool_WhenEveryCallBlocks_StartsThemAll() async {
    let count = Self.blockingCalls
    let started = OSAllocatedUnfairLock(initialState: 0)
    let release = DispatchSemaphore(value: 0)
    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<count {
        group.addTask {
          _ = await offCooperativePool {
            started.withLock { $0 += 1 }
            release.wait()
          }
        }
      }
      let deadline = ContinuousClock.now + .seconds(5)
      while started.withLock({ $0 }) < count, ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(50))
      }
      let running = started.withLock { $0 }
      for _ in 0..<count {
        release.signal()
      }
      #expect(running == count)
    }
  }
}

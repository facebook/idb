/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBProfilingCore
import Foundation
import Testing

@Suite
struct ProfileOperationTests {

  private static let stopped = ProfileResult(report: nil, toolOutput: Data("stopped".utf8), artifact: nil)

  @Test
  func stoppingAStoppableProfilerReportsWhatItHas() async throws {
    let operation = ProfileOperation(stoppable: { stop in
      try await stop.wait()
      return Self.stopped
    })

    operation.stop()

    #expect(try await operation.result.toolOutput == Self.stopped.toolOutput)
  }

  @Test
  func stoppingAProfilerThatRunsToCompletionCancelsIt() async {
    let operation = ProfileOperation {
      try await Task.sleep(for: .seconds(60))
      return Self.stopped
    }

    operation.stop()

    await #expect(throws: CancellationError.self) { try await operation.result }
  }

  @Test
  func cancellingAStoppableProfilerAbandonsIt() async {
    let operation = ProfileOperation(stoppable: { stop in
      try await stop.wait()
      return Self.stopped
    })

    operation.cancel()

    await #expect(throws: CancellationError.self) { try await operation.result }
  }
}

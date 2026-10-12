/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBArtifactStaging
import Foundation
import Testing

/// The queue between an extractor's decoding thread and its writers.
@Suite
struct ParallelFileWriterTests {

  private static func file(_ index: Int, size: Int) -> ParallelFileWriter.File {
    ParallelFileWriter.File(path: "/nonexistent/\(index)", contents: Data(count: size), mode: nil, modified: nil, extendedAttributes: [:])
  }

  /// A decoder that stays ahead of the writers never lets the queue empty, so what the queue holds has to fall as files
  /// are taken, not only once it is empty.
  @Test
  func aFileTakenByAWriterIsNoLongerHeld() throws {
    let queue = ParallelFileWriter.WriteQueue()
    let size = 1 << 20
    for index in 0..<4 {
      try queue.put(Self.file(index, size: size))
    }
    for _ in 0..<3 {
      #expect(queue.take() != nil)
    }
    // BUG: taken files stay in the queue until it empties, so it holds all four rather than the one waiting — flipped
    // in the following commit.
    #expect(queue.heldBytes == 4 * size)
  }
}

/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionUtilities
import Testing

@Suite
struct FIFOStreamWriterTests {

  private static let maxValue: Int = 1_000
  let sequentialValues = (0...maxValue).map({ $0 })
  private var mockWriter = MockStreamWriter(terminator: maxValue)

  init() {
    mockWriter = .init(terminator: Self.maxValue)
  }

  @Test
  func fifoOrder() async throws {
    let fifoWrapper = FIFOStreamWriter(stream: mockWriter)
    try await confirmation("completion") { confirm in
      mockWriter.completion = { confirm() }

      for value in sequentialValues {
        try fifoWrapper.send(value)
      }
    }

    #expect(sequentialValues == mockWriter.storage)
  }
}

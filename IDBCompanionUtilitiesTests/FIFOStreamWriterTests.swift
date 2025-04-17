/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest

@testable import IDBCompanionUtilities

class FIFOStreamWriterTests: XCTestCase {

  private static let maxValue: Int = 1_000
  let sequentialValues = (0...maxValue).map({ $0 })
  private var mockWriter = MockStreamWriter(terminator: maxValue)

  override func setUp() {
    mockWriter = .init(terminator: Self.maxValue)
  }

  func testFIFOOrder() throws {
    let expectation = expectation(description: #function)
    let fifoWrapper = FIFOStreamWriter(stream: mockWriter)
    mockWriter.completion = { expectation.fulfill() }

    for value in sequentialValues {
      try fifoWrapper.send(value)
    }

    wait(for: [expectation], timeout: 2)

    XCTAssertEqual(sequentialValues, mockWriter.storage)
  }
}

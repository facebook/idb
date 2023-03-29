/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import IDBCompanionUtilities

enum MockStreamError: Error {
  case completionIsNil
}

class MockStreamWriter: AsyncStreamWriter {

  let terminator: Int

  @Atomic var storage: [Int] = []

  var completion: (() -> Void)?

  init(terminator: Int) {
    self.terminator = terminator
  }

  func send(_ value: Int) async throws {
    _storage.sync { $0.append(value) }

    if value == terminator {
      guard let completion else {
        throw MockStreamError.completionIsNil
      }
      completion()
    }
  }
}

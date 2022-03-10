/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

extension AsyncSequence {

  var next: Element? {
    get async throws {
      return try await first(where: { _ in true })
    }
  }

}

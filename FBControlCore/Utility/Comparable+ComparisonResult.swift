/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

extension Comparable {

  /// Orders `self` against `other` as a Foundation `ComparisonResult`.
  func compared(to other: Self) -> ComparisonResult {
    self < other ? .orderedAscending : self > other ? .orderedDescending : .orderedSame
  }
}

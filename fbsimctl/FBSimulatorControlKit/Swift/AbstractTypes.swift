/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/**
 A means by which to accumulate state into a value (think Monoid-like).
 Accumulator.init() is the identity of the value.
 */
public protocol Accumulator {
  init()
  func append(_ other: Self) -> Self
}

/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import Foundation

/**
 A means by which to accumilate state into a value (think Monoid-like).
 Accumilator.init() is the identity of the value.
 */
public protocol Accumilator {
  init()
  func append(other: Self) -> Self
}

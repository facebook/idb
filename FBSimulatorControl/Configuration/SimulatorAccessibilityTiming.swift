/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// How long an accessibility read may take, on every backend: per element, and for the whole query.
///
/// A read that runs out of either fails with an error saying the simulator's accessibility service did not
/// answer, rather than waiting on or returning a tree with values missing. Retrying is safe.
public struct SimulatorAccessibilityTiming: Sendable, Hashable {
  /// The longest one element's request may go unanswered.
  public var elementTimeout: TimeInterval
  /// The longest the whole query may take, from resolving its root to its last element.
  public var queryTimeout: TimeInterval

  public init(elementTimeout: TimeInterval = 5, queryTimeout: TimeInterval = 10) {
    self.elementTimeout = elementTimeout
    self.queryTimeout = queryTimeout
  }

  public static let `default` = SimulatorAccessibilityTiming()
}

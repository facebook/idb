/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

// Default bridge implementation against the legacy `FBAccessibilityOperations`
// protocol. Lives in `FBSimulatorControl` rather than `FBControlCore` because
// `FBAccessibilityElement` is implemented here, and specializing
// `bridgeFBFuture<FBAccessibilityElement>` requires the class symbol at link
// time.
extension AsyncAccessibilityOperations where Self: FBAccessibilityOperations {

  public func accessibilityElement(at point: CGPoint) async throws -> FBAccessibilityElement {
    try await bridgeFBFuture(self.accessibilityElement(at: point))
  }

  public func accessibilityElementForFrontmostApplication() async throws -> FBAccessibilityElement {
    try await bridgeFBFuture(self.accessibilityElementForFrontmostApplication())
  }

  public func accessibilityElementMatching(
    value: String,
    forKey key: FBAXSearchableKey,
    depth: UInt
  ) async throws -> FBAccessibilityElement {
    try await bridgeFBFuture(self.accessibilityElementMatchingValue(value, forKey: key, depth: depth))
  }
}

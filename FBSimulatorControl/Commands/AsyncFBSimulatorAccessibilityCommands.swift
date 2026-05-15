/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

// MARK: - FBSimulator+AsyncAccessibilityCommands

extension FBSimulator: AsyncAccessibilityCommands {

  public func accessibilityElement(at point: CGPoint) async throws -> FBAccessibilityElement {
    try await bridgeFBFuture(accessibilityCommands().accessibilityElement(at: point))
  }

  public func accessibilityElementForFrontmostApplication() async throws -> FBAccessibilityElement {
    try await bridgeFBFuture(accessibilityCommands().accessibilityElementForFrontmostApplication())
  }

  public func accessibilityElementMatching(
    value: String,
    forKey key: FBAXSearchableKey,
    depth: UInt
  ) async throws -> FBAccessibilityElement {
    let cmds: any FBAccessibilityOperations = try accessibilityCommands()
    return try await bridgeFBFuture(cmds.accessibilityElementMatchingValue(value, forKey: key, depth: depth))
  }
}

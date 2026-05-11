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

// Explicit conformance so `as? AsyncAccessibilityCommands` succeeds and so the
// executor can hold an `AsyncAccessibilityCommands` reference. Default impls
// above (via `where Self: FBAccessibilityOperations`) supply the methods.
extension FBSimulatorAccessibilityCommands: AsyncAccessibilityCommands {}

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

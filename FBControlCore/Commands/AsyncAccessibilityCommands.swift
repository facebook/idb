/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Swift-native async/await counterpart of `FBAccessibilityOperations`.
public protocol AsyncAccessibilityOperations: AnyObject {

  func accessibilityElement(at point: CGPoint) async throws -> FBAccessibilityElement

  func accessibilityElementForFrontmostApplication() async throws -> FBAccessibilityElement

  func accessibilityElementMatching(
    value: String,
    forKey key: FBAXSearchableKey,
    depth: UInt
  ) async throws -> FBAccessibilityElement
}

/// Swift-native async/await counterpart of `FBAccessibilityCommands`.
public protocol AsyncAccessibilityCommands: AsyncAccessibilityOperations {}

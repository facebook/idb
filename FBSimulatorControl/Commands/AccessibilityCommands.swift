/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

public protocol AccessibilityOperations: AnyObject {

  func accessibilityElement(at point: CGPoint) async throws -> FBAccessibilityElement

  func accessibilityElementForFrontmostApplication() async throws -> FBAccessibilityElement

  func accessibilityElementMatching(
    value: String,
    forKey key: FBAXSearchableKey,
    depth: UInt
  ) async throws -> FBAccessibilityElement
}

public protocol AccessibilityCommands: AccessibilityOperations {}

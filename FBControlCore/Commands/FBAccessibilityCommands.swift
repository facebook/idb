/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc public protocol FBAccessibilityOperations: NSObjectProtocol {

  @objc(accessibilityElementAtPoint:)
  func accessibilityElement(at point: CGPoint) -> FBFuture<FBAccessibilityElement>

  @objc func accessibilityElementForFrontmostApplication() -> FBFuture<FBAccessibilityElement>

  @objc(accessibilityElementMatchingValue:forKey:depth:)
  func accessibilityElementMatchingValue(_ value: String, forKey key: FBAXSearchableKey, depth: UInt) -> FBFuture<FBAccessibilityElement>
}

@objc public protocol FBAccessibilityCommands: NSObjectProtocol, FBiOSTargetCommand, FBAccessibilityOperations {
}

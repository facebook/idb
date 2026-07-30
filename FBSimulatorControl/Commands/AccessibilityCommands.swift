/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

protocol AccessibilityOperations: AnyObject {

  /// Resolves a query to a concrete accessibility element via the point / matching / frontmost
  /// mechanism. Callers own the returned element and must `close()` it.
  func resolveElement(for query: FBAccessibilityElementQuery) async throws -> FBAccessibilityElement
}

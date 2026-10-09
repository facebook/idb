/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBAXCore
import FBControlCore
import FBSimulatorControl
import Foundation

protocol AccessibilityOperations: AnyObject {

  /// Resolves a query to a concrete accessibility element via the point / matching / frontmost
  /// mechanism. `clientType` is carried by every translator request made for the element, from
  /// resolution through serialization. Callers own the returned element and must `close()` it.
  func resolveElement(for query: AccessibilityElementQuery, clientType: AXClientType) async throws -> AccessibilityElement
}

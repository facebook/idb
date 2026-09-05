/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// How a describe read is rendered. Raw values are the CLI tokens.
public enum FBAccessibilityOutputFormat: String, CaseIterable, Sendable {
  /// The elements flattened into one array, each node carrying no children.
  case `default`
  /// The elements as a tree, each node carrying its `children`.
  case nested
  /// A consolidated document: the element tree plus the read's blocking modal, truncation, screen
  /// bounds and backend/target provenance, and any profiling/coverage that was collected.
  case complete
}

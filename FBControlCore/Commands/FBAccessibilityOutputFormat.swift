/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// How a describe read is rendered. One value replaces the older "nested or not" boolean, so a format
/// that is neither flat nor nested — `complete` — is representable without a second flag whose
/// combinations would need policing.
///
/// The raw values are the CLI tokens verbatim, so a front-end can accept the format without restating
/// the cases or mapping them onto a parallel enum of its own.
public enum FBAccessibilityOutputFormat: String, CaseIterable, Sendable {
  /// The elements flattened into one array, each node carrying no children.
  case `default`
  /// The elements as a tree, each node carrying its `children`.
  case nested
  /// A consolidated document: the element tree plus the read's blocking modal, truncation, screen
  /// bounds and backend/target provenance, and any profiling/coverage that was collected.
  case complete
}

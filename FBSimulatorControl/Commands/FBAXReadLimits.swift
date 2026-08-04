/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// The bounds every whole-tree read is taken under, shared by both XCUI-grade backends (the
/// `testmanagerd` remote-automation session and the `axbridge` guest reader) so their output is
/// comparable: a tree read over one backend truncates at the same point as the other.
///
/// These are authoritative. The host sends them on every request, so the guest reader truncates to
/// these rather than keeping its own copy. The guest keeps a *separate*, larger fallback pair
/// (`kDefaultMaxDepth` = 100 / `kDefaultNodeBudget` = 5000 in `AccessibilityService.m`) that applies
/// only when a request omits the bounds — e.g. the one-shot guest front-end invoked by hand. The two
/// must not be conflated: a host-driven read always truncates at 50 / 3000.
enum FBAXReadLimits {
  static let maxReadDepth = 50
  static let maxReadNodes = 3000
}

/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Remediation appended to the accessibility errors a user can act on.
///
/// Kept apart from the error types that quote it because more than one of them does, and apart from
/// the read path because none of this is about reading — it is what to tell someone whose read did not
/// work. An error case appends a member here only when that remedy plausibly fixes *that* case;
/// guidance attached to every failure alike teaches the reader to ignore it.
enum FBAccessibilityGuidance {

  /// For a target whose in-process accessibility server never started. The flag is read at launch and
  /// consumed (a live read clears it), so it is an unreliable thing to gate a read on up front — hence
  /// guidance on the failure rather than a precondition check on the way in.
  static let accessibilityServer = "If reads consistently return nothing, the app's accessibility server is likely not running: set ApplicationAccessibilityEnabled (com.apple.Accessibility) before the app launches — e.g. `xcrun simctl spawn <UDID> defaults write com.apple.Accessibility ApplicationAccessibilityEnabled -bool true` — then relaunch the app."
}

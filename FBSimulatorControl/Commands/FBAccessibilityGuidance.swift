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

  /// A read where most elements report no rectangle is *sometimes* a container caching stale children:
  /// UIKit caches a container's children and invalidates only on that container's own direct subview
  /// changes, so a screen pushed below one leaves the cache naming views that have since left the window
  /// — and a view out of its window reports a zero rect while keeping its label. Automation mode does not
  /// take that caching branch.
  ///
  /// Advice, not a diagnosis. There is no error to attach this to: such a read succeeds, reports
  /// `truncated: false`, and looks healthy on every count- and size-based measure. Geometry is the only
  /// attribute that degrades with it, which is why the tally is worth saying something about.
  static let automationMode = "Most elements in this read carry no frame. If the tree describes a screen other than the one displayed, the target may be caching stale accessibility children: set AutomationEnabled (com.apple.Accessibility) — e.g. `xcrun simctl spawn <UDID> defaults write com.apple.Accessibility AutomationEnabled -bool true` — which takes effect on the next read without relaunching."

  /// Reads below this are not judged. A handful of elements with no frame is ordinary; the same ratio
  /// over a whole screen is not, and a small read has no statistical claim either way.
  private static let minimumElementsToJudge = 20

  /// A quarter. Every clean read measured while investigating this came back at zero zero-framed
  /// elements, and every faulted one between 38% and 90%, so anywhere in that gap separates them. A
  /// quarter is chosen to sit well clear of zero rather than close to the faults, because the cost of
  /// being wrong is asymmetric: a spurious line of advice is cheap, and the sample of *clean* reads
  /// behind this number is two applications rather than a fleet.
  private static let suspectZeroFrameRatio = 0.25

  /// Advice for a read whose geometry looks degenerate, or nil when it does not.
  ///
  /// This is the one place in the read path where a threshold is acceptable. Everywhere else — the tally
  /// itself, the telemetry tags — reports raw counts and leaves judgement to whoever knows which screen
  /// they are looking at, because being wrong there produces a wrong answer. Being wrong here produces a
  /// line of advice a reader can ignore.
  static func suspectGeometry(_ frames: FBAccessibilityFrameSummary?) -> String? {
    guard let frames, frames.total >= minimumElementsToJudge else {
      return nil
    }
    let ratio = Double(frames.zeroFrame) / Double(frames.total)
    return ratio >= suspectZeroFrameRatio ? automationMode : nil
  }
}

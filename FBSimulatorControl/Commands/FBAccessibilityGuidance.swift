/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Remediation text appended to the accessibility errors a user can act on. An error case appends a
/// member only when that remedy plausibly fixes that specific failure; guidance attached to every
/// failure alike teaches the reader to ignore it.
enum FBAccessibilityGuidance {

  /// For a target whose in-process accessibility server never started. The flag is read at launch and
  /// consumed — a live read clears it — so it cannot be checked reliably up front.
  static let accessibilityServer = "If reads consistently return nothing, the app's accessibility server is likely not running: set ApplicationAccessibilityEnabled (com.apple.Accessibility) before the app launches — e.g. `xcrun simctl spawn <UDID> defaults write com.apple.Accessibility ApplicationAccessibilityEnabled -bool true` — then relaunch the app."

  /// A read where most elements report no rectangle is *sometimes* a container caching stale children:
  /// UIKit invalidates a container's cached children only on that container's own direct subview
  /// changes, and a view out of its window reports a zero rect while keeping its label. Automation
  /// mode does not take that caching branch.
  static let automationMode = "Most elements in this read carry no frame. If the tree describes a screen other than the one displayed, the target may be caching stale accessibility children: set AutomationEnabled (com.apple.Accessibility) — e.g. `xcrun simctl spawn <UDID> defaults write com.apple.Accessibility AutomationEnabled -bool true` — which takes effect on the next read without relaunching."

  /// For a whole-tree read that asked for reachability, which the application answers by hit-testing
  /// every node (see `FBAXKeys.interactable`). Logged at the read because the read still succeeds, so
  /// nothing else in the output explains the latency.
  static let reachabilityAcrossTree = "Requesting reachability (interactable / occluded_by) across a whole tree makes the application hit-test every node, which is usually the dominant cost of the read. For a single element, use `ui describe-point <x> <y> --key interactable` instead."

  /// Reads below this are not judged: a handful of elements with no frame is ordinary, and below this
  /// size the ratio is noise.
  private static let minimumElementsForRatio = 20

  /// Observed clean reads: 0% zero-framed elements; faulted reads: 38-90%. A quarter sits well clear
  /// of zero; note the clean-read sample was small.
  private static let zeroFrameWarningRatio = 0.25

  /// Advice for a read whose geometry looks degenerate, or nil when it does not. A threshold
  /// heuristic; a wrong answer here only costs an ignorable advice line.
  static func zeroFrameAdvice(_ frames: FBAccessibilityFrameSummary?) -> String? {
    guard let frames, frames.total >= minimumElementsForRatio else {
      return nil
    }
    let ratio = Double(frames.zeroFrame) / Double(frames.total)
    return ratio >= zeroFrameWarningRatio ? automationMode : nil
  }
}

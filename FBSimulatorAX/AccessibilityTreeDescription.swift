/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import Foundation

/// A whole-tree read once serialized: every element walked, the ones the request reports, and the coverage
/// and narrowing report derived from them. Both backends describe a tree through this, so filtering,
/// matching, coverage and the narrowing counts are decided in one place; each backend reads its own way
/// and adds only what is its own around it — remote content on the translator, per-element reachability on
/// axbridge.
struct AccessibilityTreeDescription {
  let walked: [AccessibilityDocumentElement]
  private(set) var reported: [AccessibilityDocumentElement]
  /// The bounds frames are measured against; nil when the read could not tell, which leaves coverage
  /// unmeasured.
  let screenBounds: CGRect?
  private let options: AccessibilityRequestOptions

  init(walked: [AccessibilityDocumentElement], options: AccessibilityRequestOptions, screenBounds: CGRect?) {
    self.walked = walked
    self.reported = options.narrowing(walked, screen: screenBounds)
    self.screenBounds = screenBounds
    self.options = options
  }

  /// Replaces the reported elements with `refinement` of them. Runs after narrowing, so per-element work
  /// is never spent on an element the request drops.
  mutating func refineReported(
    _ refinement: ([AccessibilityDocumentElement]) async throws -> [AccessibilityDocumentElement]
  ) async rethrows {
    reported = try await refinement(reported)
  }

  /// The frame coverage of the reported elements, when the request asked for it and the screen is known.
  /// `additional` is coverage found beyond the tree, by remote-content discovery.
  func coverage(additional: Double? = nil) -> AccessibilityCoverage? {
    guard options.collectFrameCoverage, let screenBounds else {
      return nil
    }
    return .measured(
      reported: reported, walked: walked, screenBounds: screenBounds, nested: options.nestedFormat,
      additional: additional)
  }

  /// What narrowed the read. `discovered` elements were walked too, so a read never reports more matched
  /// than walked; `elements` is what the response finally reports, when that is more than `reported`.
  func narrowingReport(
    reporting elements: [AccessibilityDocumentElement]? = nil, discovered: [AccessibilityDocumentElement] = []
  ) -> AccessibilityNarrowing {
    AccessibilityNarrowing(
      filter: options.filter, match: options.match, walked: walked, discovered: discovered, reported: elements ?? reported)
  }
}

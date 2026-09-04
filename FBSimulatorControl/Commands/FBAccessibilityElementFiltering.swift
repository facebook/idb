/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// Narrowing a serialized read to the elements a caller asked for. Both narrowings decide what a read
/// reports, never where the walk goes.
enum FBAccessibilityElementRetention {

  /// The elements `keeps` accepts, hoisting a dropped element's kept descendants into its place.
  ///
  /// Hoisting is what stops a narrowing over-reaching: a matching button nested inside an unlabeled
  /// container is kept, taking the container's position, rather than being lost with it. Without it a
  /// filter would report a screen as empty whenever the app happened to wrap its content.
  ///
  /// Shape is preserved rather than normalized: a flat read's elements carry no `children` key and must
  /// not grow one, so an element whose `children` is `nil` keeps it `nil`.
  static func retaining(
    _ elements: [FBAccessibilityDocumentElement],
    where keeps: (FBAccessibilityDocumentElement) -> Bool
  ) -> [FBAccessibilityDocumentElement] {
    elements.flatMap { retained(from: $0, where: keeps) }
  }

  /// `element` if it passes, otherwise the kept descendants that take its place.
  private static func retained(
    from element: FBAccessibilityDocumentElement,
    where keeps: (FBAccessibilityDocumentElement) -> Bool
  ) -> [FBAccessibilityDocumentElement] {
    let keptChildren = (element.children ?? []).flatMap { retained(from: $0, where: keeps) }
    guard keeps(element) else {
      return keptChildren
    }
    var kept = element
    if element.children != nil {
      kept.children = keptChildren
    }
    return [kept]
  }
}

extension FBAccessibilityElementFilter {

  /// The elements this filter keeps, with their kept descendants hoisted into the place of anything
  /// dropped. `.all` is the identity, and returns the input untouched rather than rebuilding it.
  func apply(to elements: [FBAccessibilityDocumentElement]) -> [FBAccessibilityDocumentElement] {
    guard self != .all else {
      return elements
    }
    return FBAccessibilityElementRetention.retaining(elements, where: keeps)
  }

  /// Whether an element survives this filter.
  ///
  /// `.interactable` asks the backend's own verdict, so a covered, disabled or zero-sized element is
  /// dropped however button-like it looks. The structural heuristic — a label, an identifier, or an
  /// actionable role — applies only when the backend returned no verdict.
  ///
  /// An attribute the read did not serialize cannot be matched on, which is why requesting a filter
  /// widens the serialized key set (`FBAccessibilityRequestOptions.serializationKeys`).
  private func keeps(_ element: FBAccessibilityDocumentElement) -> Bool {
    switch self {
    case .all:
      return true
    case .interactable:
      if let verdict = element.interactable ?? nil {
        guard case .actionable = verdict else {
          return false
        }
        return true
      }
      if let label = element.label ?? nil, !label.isEmpty {
        return true
      }
      if let identifier = element.identifier ?? nil, !identifier.isEmpty {
        return true
      }
      if let role = element.role ?? nil, FBAXRoleVocabulary.isInteractable(role: role) {
        return true
      }
      return false
    }
  }
}

extension FBAccessibilityMatch {

  /// The elements whose `key` value contains this match's `value`, hoisted like the filter. No match is
  /// an empty list, not an error: `--match` reporting nothing is a true answer about the screen.
  func apply(to elements: [FBAccessibilityDocumentElement]) -> [FBAccessibilityDocumentElement] {
    FBAccessibilityElementRetention.retaining(elements, where: keeps)
  }

  /// Whether an element's searched attribute contains the substring. An element that does not carry the
  /// attribute — or a read that did not serialize it — does not match; `serializationKeys` unions the
  /// searched key in so the second case does not arise from a narrow `--key`.
  private func keeps(_ element: FBAccessibilityDocumentElement) -> Bool {
    matches(element.searchableValue(for: key))
  }
}

extension FBAccessibilityElementRetention {

  /// Both narrowings in the order a read applies them: the filter says which elements are worth
  /// reporting at all, the match says which of those the caller was looking for.
  ///
  /// The order lives here, in one place, because it is observable: both hoist, so filtering a matching
  /// element's container away before the match runs is not the same as after.
  static func narrowing(
    _ elements: [FBAccessibilityDocumentElement],
    filter: FBAccessibilityElementFilter,
    match: FBAccessibilityMatch?
  ) -> [FBAccessibilityDocumentElement] {
    let filtered = filter.apply(to: elements)
    return match.map { $0.apply(to: filtered) } ?? filtered
  }
}

extension FBAccessibilityRequestOptions {

  /// The elements a describe-all read reports out of what it walked.
  func narrowing(_ elements: [FBAccessibilityDocumentElement]) -> [FBAccessibilityDocumentElement] {
    FBAccessibilityElementRetention.narrowing(elements, filter: filter, match: match)
  }
}

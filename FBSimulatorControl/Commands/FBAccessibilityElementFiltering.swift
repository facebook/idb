/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// Applying `FBAccessibilityElementFilter` to a serialized read.
///
/// The filter is an output concern, not a traversal one: it decides what a read *reports*, never where
/// the walk goes. Expressing it over the serialized model rather than inside the walk is what makes it
/// one implementation for every backend — the accessibility walk over live elements and the guest
/// backends' walk over a materialized attribute tree produce the same model, so they can only agree
/// here.
///
/// It also makes the predicate testable without a simulator: it reads the attributes off the element
/// instead of calling back into the platform for them.
extension FBAccessibilityElementFilter {

  /// The elements this filter keeps, hoisting a dropped element's kept descendants into its place.
  ///
  /// Hoisting is what stops the filter over-reaching: an interactable element nested inside an
  /// unlabeled container is kept, taking the container's position, rather than being lost with it.
  ///
  /// Shape is preserved rather than normalized. A flat read's elements carry no `children` key and must
  /// not grow one, so an element whose `children` is `nil` keeps it `nil`; the flat list is one level
  /// deep, and filtering it is the degenerate case of the same recursion.
  func apply(to elements: [FBAccessibilityDocumentElement]) -> [FBAccessibilityDocumentElement] {
    guard self != .all else {
      return elements
    }
    return elements.flatMap { keptElements(from: $0) }
  }

  /// `element` if it passes, otherwise the kept descendants that take its place.
  private func keptElements(from element: FBAccessibilityDocumentElement) -> [FBAccessibilityDocumentElement] {
    let keptChildren = (element.children ?? []).flatMap { keptElements(from: $0) }
    guard keeps(element) else {
      return keptChildren
    }
    var kept = element
    if element.children != nil {
      kept.children = keptChildren
    }
    return [kept]
  }

  /// Whether an element survives this filter. `.interactable` keeps elements carrying a label, an
  /// identifier, or an actionable role — dropping the unlabeled structural containers that make up most
  /// of a tree.
  ///
  /// An attribute the read did not serialize cannot be matched on, which is why requesting a filter
  /// widens the serialized key set (`FBAccessibilityRequestOptions.serializationKeys`).
  private func keeps(_ element: FBAccessibilityDocumentElement) -> Bool {
    switch self {
    case .all:
      return true
    case .interactable:
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

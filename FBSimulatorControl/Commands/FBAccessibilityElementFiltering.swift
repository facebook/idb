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
/// The filter decides what a read *reports*, never where the walk goes. Running it over the
/// serialized model gives one implementation for every backend, testable without a simulator.
extension FBAccessibilityElementFilter {

  /// The elements this filter keeps, hoisting a dropped element's kept descendants into its place.
  ///
  /// Hoisting is what stops the filter over-reaching: an interactable element nested inside an
  /// unlabeled container is kept, taking the container's position, rather than being lost with it.
  ///
  /// Shape is preserved rather than normalized: a flat read's elements carry no `children` key and
  /// must not grow one, so an element whose `children` is `nil` keeps it `nil`.
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

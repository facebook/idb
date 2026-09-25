/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import FBControlCore
import Foundation

/// Narrowing a serialized read to the elements a caller asked for. Both narrowings decide what a read
/// reports, never where the walk goes.
enum AccessibilityElementRetention {

  /// The elements `keeps` accepts, hoisting a dropped element's kept descendants into its place.
  ///
  /// Hoisting is what stops a narrowing over-reaching: a matching button nested inside an unlabeled
  /// container is kept, taking the container's position, rather than being lost with it. Without it a
  /// filter would report a screen as empty whenever the app happened to wrap its content.
  ///
  /// Shape is preserved rather than normalized: a flat read's elements carry no `children` key and must
  /// not grow one, so an element whose `children` is `nil` keeps it `nil`.
  ///
  /// An element `prunes` accepts is dropped with its whole subtree, nothing hoisted.
  static func retaining(
    _ elements: [AccessibilityDocumentElement],
    where keeps: (AccessibilityDocumentElement) -> Bool,
    pruning prunes: (AccessibilityDocumentElement) -> Bool = { _ in false }
  ) -> [AccessibilityDocumentElement] {
    elements.flatMap { retained(from: $0, where: keeps, pruning: prunes) }
  }

  /// `element` if it passes, otherwise the kept descendants that take its place.
  private static func retained(
    from element: AccessibilityDocumentElement,
    where keeps: (AccessibilityDocumentElement) -> Bool,
    pruning prunes: (AccessibilityDocumentElement) -> Bool
  ) -> [AccessibilityDocumentElement] {
    guard !prunes(element) else {
      return []
    }
    let keptChildren = (element.children ?? []).flatMap { retained(from: $0, where: keeps, pruning: prunes) }
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

extension AccessibilityElementFilter {

  /// The elements this filter keeps, with their kept descendants hoisted into the place of anything
  /// dropped. `.all` is the identity, and returns the input untouched rather than rebuilding it.
  ///
  /// `screen` is the rectangle the elements' frames are in. Nothing is judged against a nil or empty one:
  /// a read that could not measure its screen must not report the screen as empty.
  func apply(to elements: [AccessibilityDocumentElement], screen: CGRect?) -> [AccessibilityDocumentElement] {
    guard self != .all else {
      return elements
    }
    return AccessibilityElementRetention.retaining(
      elements, where: keeps, pruning: { Self.liesOutside($0, screen: screen) }
    )
  }

  /// Whether an element's frame lies wholly outside the screen. Its subtree goes with it, unjudged: the
  /// runtime reports the descendants of an offscreen table row in the row's own coordinates, so their
  /// frames would place them on screen. An empty frame is never outside: a zero-sized container can
  /// hold on-screen elements.
  private static func liesOutside(_ element: AccessibilityDocumentElement, screen: CGRect?) -> Bool {
    guard let screen, !screen.isEmpty, let rect = (element.frame ?? nil)?.rect, !rect.isEmpty else {
      return false
    }
    return !rect.intersects(screen)
  }

  /// Whether an element survives this filter.
  ///
  /// `.interactable` asks the backend's own verdict, so a covered, disabled or zero-sized element is
  /// dropped however button-like it looks. The structural heuristic — a label, an identifier, or an
  /// actionable role on an element that is not zero-sized — applies only when the backend returned no
  /// verdict.
  ///
  /// An attribute the read did not serialize cannot be matched on, which is why requesting a filter
  /// widens the serialized key set (`AccessibilityRequestOptions.serializationKeys`).
  private func keeps(_ element: AccessibilityDocumentElement) -> Bool {
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
      // A zero-sized element cannot be touched. Its children are judged on their own frames: a
      // zero-sized container can hold on-screen elements.
      if let rect = (element.frame ?? nil)?.rect, rect.isEmpty {
        return false
      }
      if let label = element.label ?? nil, !label.isEmpty {
        return true
      }
      if let identifier = element.identifier ?? nil, !identifier.isEmpty {
        return true
      }
      if let role = element.role ?? nil, AXRoleVocabulary.isInteractable(role: role) {
        return true
      }
      return false
    }
  }
}

extension AccessibilityMatch {

  /// The elements whose `key` value contains this match's `value`, hoisted like the filter. No match is
  /// an empty list, not an error: `--match` reporting nothing is a true answer about the screen.
  func apply(to elements: [AccessibilityDocumentElement]) -> [AccessibilityDocumentElement] {
    AccessibilityElementRetention.retaining(elements, where: keeps)
  }

  /// Whether an element's searched attribute contains the substring. An element that does not carry the
  /// attribute — or a read that did not serialize it — does not match; `serializationKeys` unions the
  /// searched key in so the second case does not arise from a narrow `--key`.
  private func keeps(_ element: AccessibilityDocumentElement) -> Bool {
    matches(element.searchableValue(for: key))
  }
}

extension AccessibilityElementRetention {

  /// Both narrowings in the order a read applies them: the filter says which elements are worth
  /// reporting at all, the match says which of those the caller was looking for.
  ///
  /// The order lives here, in one place, because it is observable: both hoist, so filtering a matching
  /// element's container away before the match runs is not the same as after.
  static func narrowing(
    _ elements: [AccessibilityDocumentElement],
    filter: AccessibilityElementFilter,
    match: AccessibilityMatch?,
    screen: CGRect?
  ) -> [AccessibilityDocumentElement] {
    let filtered = filter.apply(to: elements, screen: screen)
    return match.map { $0.apply(to: filtered) } ?? filtered
  }
}

extension AccessibilityRequestOptions {

  /// The elements a describe-all read reports out of what it walked, whose frames are in `screen`.
  func narrowing(_ elements: [AccessibilityDocumentElement], screen: CGRect?) -> [AccessibilityDocumentElement] {
    AccessibilityElementRetention.narrowing(elements, filter: filter, match: match, screen: screen)
  }
}

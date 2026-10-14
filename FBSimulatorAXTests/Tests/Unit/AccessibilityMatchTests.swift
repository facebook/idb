/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorAX
@testable import FBSimulatorControl
import Foundation
import Testing

/// `AccessibilityMatch` — the substring narrowing behind `describe-all --match` — and the hoisting it
/// shares with `AccessibilityElementFilter`.
///
/// Pure functions over the serialized model, so none of this needs a simulator.
@Suite
struct AccessibilityMatchTests {

  private static func element(
    label: String? = nil,
    identifier: String? = nil,
    value: String? = nil,
    role: String? = nil,
    children: [AccessibilityDocumentElement]? = nil
  ) -> AccessibilityDocumentElement {
    var element = AccessibilityDocumentElement()
    if let label {
      element.label = .some(label)
    }
    if let identifier {
      element.identifier = .some(identifier)
    }
    if let value {
      element.value = .some(.string(value))
    }
    if let role {
      element.role = .some(role)
    }
    element.children = children
    return element
  }

  private static func labels(_ elements: [AccessibilityDocumentElement]) -> [String] {
    elements.compactMap { $0.label ?? nil }
  }

  private static func match(
    _ value: String, key: AXSearchableKey = .label, ignoresCase: Bool = false
  ) throws -> AccessibilityMatch {
    try #require(AccessibilityMatch(value: value, key: key, ignoresCase: ignoresCase))
  }

  // MARK: - What matches

  @Test
  func theMatchKeepsEveryElementWhoseLabelContainsTheSubstring() throws {
    let read = [
      Self.element(label: "Add to Cart"),
      Self.element(label: "Remove from Cart"),
      Self.element(label: "Checkout"),
    ]
    #expect(Self.labels(try Self.match("Cart").apply(to: read)) == ["Add to Cart", "Remove from Cart"])
  }

  // Substring, not equality — the contract documented on `AccessibilityElementQuery.marker`.
  @Test
  func theMatchIsASubstringNotAnEquality() throws {
    let read = [Self.element(label: "Add to Cart")]
    #expect(Self.labels(try Self.match("to Ca").apply(to: read)) == ["Add to Cart"])
  }

  // Unlike `describe MARKER` (which throws `elementNotFound`), no match is an empty list.
  @Test
  func noMatchIsAnEmptyListRatherThanAFailure() throws {
    #expect(try Self.match("Cart").apply(to: [Self.element(label: "Checkout")]).isEmpty)
  }

  @Test
  func anEmptyMatchValueIsNoMatchAtAll() {
    #expect(
      AccessibilityMatch(value: "") == nil,
      "an empty match would keep every element, which is the absence of a match rather than one"
    )
  }

  // MARK: - Case

  @Test
  func theMatchIsCaseSensitiveByDefault() throws {
    #expect(try Self.match("cart").apply(to: [Self.element(label: "Add to Cart")]).isEmpty)
  }

  @Test
  func ignoresCaseComparesCaseInsensitivelyInBothDirections() throws {
    let read = [Self.element(label: "Add to Cart"), Self.element(label: "SHOPPING BAG")]
    let matched = try Self.match("cart", ignoresCase: true).apply(to: read)
    #expect(Self.labels(matched) == ["Add to Cart"])
    #expect(
      Self.labels(try Self.match("Shopping", ignoresCase: true).apply(to: read)) == ["SHOPPING BAG"]
    )
  }

  // MARK: - Which attribute

  @Test
  func theMatchSearchesTheKeyItWasGiven() throws {
    let read = [
      Self.element(label: "Continue", identifier: "checkout-button"),
      Self.element(label: "checkout-button", identifier: "continue"),
    ]
    #expect(
      Self.labels(try Self.match("checkout", key: .uniqueID).apply(to: read)) == ["Continue"]
    )
  }

  @Test
  func theMatchReadsAStringValueAttribute() throws {
    let read = [Self.element(label: "Quantity", value: "3"), Self.element(label: "Total", value: "9")]
    #expect(Self.labels(try Self.match("3", key: .value).apply(to: read)) == ["Quantity"])
  }

  // An attribute the read did not serialize never matches either; the `serializationKeys` widening keeps that case from arising.
  @Test
  func anAbsentAttributeDoesNotMatch() throws {
    #expect(try Self.match("Cart", key: .placeholder).apply(to: [Self.element(label: "Cart")]).isEmpty)
  }

  // MARK: - Hoisting

  @Test
  func aMatchingDescendantIsHoistedIntoItsDroppedAncestorsPlace() throws {
    let read = [
      Self.element(
        label: "Product Row",
        children: [Self.element(label: "Unlabelled Stack", children: [Self.element(label: "Add to Cart")])]
      )
    ]
    let matched = try Self.match("Cart").apply(to: read)
    #expect(Self.labels(matched) == ["Add to Cart"])
    #expect((matched.first?.children ?? []) == [])
  }

  @Test
  func aMatchingAncestorKeepsOnlyItsMatchingDescendants() throws {
    let read = [
      Self.element(
        label: "Cart Row",
        children: [Self.element(label: "Remove from Cart"), Self.element(label: "Quantity")]
      )
    ]
    let matched = try Self.match("Cart").apply(to: read)
    #expect(Self.labels(matched) == ["Cart Row"])
    #expect(Self.labels(matched.first?.children ?? []) == ["Remove from Cart"])
  }

  @Test
  func aFlatReadsElementsDoNotGrowAChildrenKey() throws {
    let matched = try Self.match("Cart").apply(to: [Self.element(label: "Add to Cart")])
    #expect(matched.first?.children == nil)
  }

  // MARK: - Composition with the filter

  // Both `filter` and `match` hoist, so their order is observable when a match sits under a non-interactable container.
  @Test
  func filterThenMatchKeepsAMatchingElementUnderADroppedContainer() throws {
    var container = AccessibilityDocumentElement()
    container.interactable = .some(nil)
    container.children = [Self.element(label: "Add to Cart", role: "AXButton")]

    let filtered = AccessibilityElementFilter.interactable.apply(to: [container], screen: nil)
    #expect(Self.labels(filtered) == ["Add to Cart"], "the unlabelled container is dropped, its child hoisted")
    #expect(Self.labels(try Self.match("Cart").apply(to: filtered)) == ["Add to Cart"])
  }

  // MARK: - Serialization keys

  // The match runs over the serialized model, so the key it searches on has to be fetched — otherwise
  // `--key frame --match Buy` reports nothing rather than the buy button's frame.
  @Test
  func requestingAMatchWidensTheSerializedKeySet() throws {
    var options = AccessibilityRequestOptions(keys: [.frame])
    options.match = try Self.match("Buy", key: .placeholder)
    #expect(options.serializationKeys.contains(.placeholder))
    #expect(options.serializationKeys.contains(.frame), "the caller's own keys are not replaced")
  }

  // `complete` reports the raw `role` only through the normalized `type`, so matching on it needs the
  // counterpart the format arm already adds for a requested key.
  @Test
  func matchingOnRoleUnderCompleteAlsoSerializesItsCounterpart() throws {
    var options = AccessibilityRequestOptions(format: .complete, keys: [.label])
    options.match = try Self.match("Button", key: .role)
    #expect(options.serializationKeys.contains(.role))
    #expect(options.serializationKeys.contains(.type))
  }

  @Test
  func noMatchLeavesTheSerializedKeySetUntouched() {
    let options = AccessibilityRequestOptions(keys: [.label])
    #expect(options.serializationKeys == [.label])
  }
}

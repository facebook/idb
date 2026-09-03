/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import Foundation
import XCTest

/// `FBAccessibilityMatch` — the substring narrowing behind `describe-all --match` — and the hoisting it
/// shares with `FBAccessibilityElementFilter`.
///
/// Pure functions over the serialized model, so none of this needs a simulator.
final class FBAccessibilityMatchTests: XCTestCase {

  private static func element(
    label: String? = nil,
    identifier: String? = nil,
    value: String? = nil,
    role: String? = nil,
    children: [FBAccessibilityDocumentElement]? = nil
  ) -> FBAccessibilityDocumentElement {
    var element = FBAccessibilityDocumentElement()
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

  private static func labels(_ elements: [FBAccessibilityDocumentElement]) -> [String] {
    elements.compactMap { $0.label ?? nil }
  }

  private static func match(
    _ value: String, key: FBAXSearchableKey = .label, ignoresCase: Bool = false
  ) throws -> FBAccessibilityMatch {
    try XCTUnwrap(FBAccessibilityMatch(value: value, key: key, ignoresCase: ignoresCase))
  }

  // MARK: - What matches

  func testTheMatchKeepsEveryElementWhoseLabelContainsTheSubstring() throws {
    let read = [
      Self.element(label: "Add to Cart"),
      Self.element(label: "Remove from Cart"),
      Self.element(label: "Checkout"),
    ]
    XCTAssertEqual(Self.labels(try Self.match("Cart").apply(to: read)), ["Add to Cart", "Remove from Cart"])
  }

  // A substring, not equality — the contract `FBAccessibilityElementQuery.marker` already documents,
  // and the comparison 83% of the hand-rolled scripts this replaces were performing.
  func testTheMatchIsASubstringNotAnEquality() throws {
    let read = [Self.element(label: "Add to Cart")]
    XCTAssertEqual(Self.labels(try Self.match("to Ca").apply(to: read)), ["Add to Cart"])
  }

  // No match is an empty list, not an error. `describe MARKER` throws `elementNotFound`; this verb
  // answers a question about the screen, and "nothing" is a true answer.
  func testNoMatchIsAnEmptyListRatherThanAFailure() throws {
    XCTAssertTrue(try Self.match("Cart").apply(to: [Self.element(label: "Checkout")]).isEmpty)
  }

  func testAnEmptyMatchValueIsNoMatchAtAll() {
    XCTAssertNil(
      FBAccessibilityMatch(value: ""),
      "an empty match would keep every element, which is the absence of a match rather than one"
    )
  }

  // MARK: - Case

  func testTheMatchIsCaseSensitiveByDefault() throws {
    XCTAssertTrue(try Self.match("cart").apply(to: [Self.element(label: "Add to Cart")]).isEmpty)
  }

  func testIgnoresCaseComparesCaseInsensitivelyInBothDirections() throws {
    let read = [Self.element(label: "Add to Cart"), Self.element(label: "SHOPPING BAG")]
    let matched = try Self.match("cart", ignoresCase: true).apply(to: read)
    XCTAssertEqual(Self.labels(matched), ["Add to Cart"])
    XCTAssertEqual(
      Self.labels(try Self.match("Shopping", ignoresCase: true).apply(to: read)), ["SHOPPING BAG"]
    )
  }

  // MARK: - Which attribute

  func testTheMatchSearchesTheKeyItWasGiven() throws {
    let read = [
      Self.element(label: "Continue", identifier: "checkout-button"),
      Self.element(label: "checkout-button", identifier: "continue"),
    ]
    XCTAssertEqual(
      Self.labels(try Self.match("checkout", key: .uniqueID).apply(to: read)), ["Continue"]
    )
  }

  func testTheMatchReadsAStringValueAttribute() throws {
    let read = [Self.element(label: "Quantity", value: "3"), Self.element(label: "Total", value: "9")]
    XCTAssertEqual(Self.labels(try Self.match("3", key: .value).apply(to: read)), ["Quantity"])
  }

  // An attribute the element does not carry — or that the read did not serialize — never matches. The
  // key-set widening in `serializationKeys` is what keeps the second case from arising in practice.
  func testAnAbsentAttributeDoesNotMatch() throws {
    XCTAssertTrue(try Self.match("Cart", key: .placeholder).apply(to: [Self.element(label: "Cart")]).isEmpty)
  }

  // MARK: - Hoisting

  // The container holding the matching button is not itself labelled "Add to Cart". Dropping the button
  // along with it is the exact failure the shared hoisting exists to prevent.
  func testAMatchingDescendantIsHoistedIntoItsDroppedAncestorsPlace() throws {
    let read = [
      Self.element(
        label: "Product Row",
        children: [Self.element(label: "Unlabelled Stack", children: [Self.element(label: "Add to Cart")])]
      )
    ]
    let matched = try Self.match("Cart").apply(to: read)
    XCTAssertEqual(Self.labels(matched), ["Add to Cart"])
    XCTAssertEqual(matched.first?.children ?? [], [])
  }

  // A matching ancestor keeps only its matching descendants, not the whole subtree: the caller asked
  // which elements match, and the children of a match are not themselves matches.
  func testAMatchingAncestorKeepsOnlyItsMatchingDescendants() throws {
    let read = [
      Self.element(
        label: "Cart Row",
        children: [Self.element(label: "Remove from Cart"), Self.element(label: "Quantity")]
      )
    ]
    let matched = try Self.match("Cart").apply(to: read)
    XCTAssertEqual(Self.labels(matched), ["Cart Row"])
    XCTAssertEqual(Self.labels(matched.first?.children ?? []), ["Remove from Cart"])
  }

  // A flat read's elements carry no `children` key and must not grow one — the shape of the response is
  // the format's business, not the match's.
  func testAFlatReadsElementsDoNotGrowAChildrenKey() throws {
    let matched = try Self.match("Cart").apply(to: [Self.element(label: "Add to Cart")])
    XCTAssertNil(matched.first?.children)
  }

  // MARK: - Composition with the filter

  // `filter` then `match`, and the composition is pinned rather than argued: both hoist, so the order
  // is observable whenever a matching element sits under a non-interactable one.
  func testFilterThenMatchKeepsAMatchingElementUnderADroppedContainer() throws {
    var container = FBAccessibilityDocumentElement()
    container.interactable = .some(nil)
    container.children = [Self.element(label: "Add to Cart", role: "AXButton")]

    let filtered = FBAccessibilityElementFilter.interactable.apply(to: [container])
    XCTAssertEqual(Self.labels(filtered), ["Add to Cart"], "the unlabelled container is dropped, its child hoisted")
    XCTAssertEqual(Self.labels(try Self.match("Cart").apply(to: filtered)), ["Add to Cart"])
  }

  // MARK: - Serialization keys

  // The match runs over the serialized model, so the key it searches on has to be fetched — otherwise
  // `--key frame --match Buy` reports nothing rather than the buy button's frame.
  func testRequestingAMatchWidensTheSerializedKeySet() throws {
    var options = FBAccessibilityRequestOptions(keys: [.frame])
    options.match = try Self.match("Buy", key: .placeholder)
    XCTAssertTrue(options.serializationKeys.contains(.placeholder))
    XCTAssertTrue(options.serializationKeys.contains(.frame), "the caller's own keys are not replaced")
  }

  // `complete` reports the raw `role` only through the normalized `type`, so matching on it needs the
  // counterpart the format arm already adds for a requested key.
  func testMatchingOnRoleUnderCompleteAlsoSerializesItsCounterpart() throws {
    var options = FBAccessibilityRequestOptions(format: .complete, keys: [.label])
    options.match = try Self.match("Button", key: .role)
    XCTAssertTrue(options.serializationKeys.contains(.role))
    XCTAssertTrue(options.serializationKeys.contains(.type))
  }

  func testNoMatchLeavesTheSerializedKeySetUntouched() {
    let options = FBAccessibilityRequestOptions(keys: [.label])
    XCTAssertEqual(options.serializationKeys, [.label])
  }
}

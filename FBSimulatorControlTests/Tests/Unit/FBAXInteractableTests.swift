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

/// `interactable` over every condition it can report.
///
/// Driven through the real serializer against a guest-shaped attribute tree, so what is covered is the
/// derivation as a read actually performs it — not a hand-built sum-type value.
final class FBAXInteractableTests: XCTestCase {

  private static let occluderFrame = CGRect(x: 0, y: 791, width: 402, height: 83)

  /// A node in the shape the guest emits, with only the attributes a case needs.
  private static func node(
    frame: CGRect = CGRect(x: 134.33, y: 705, width: 133.33, height: 178.67),
    isVisible: Bool? = true,
    visiblePoint: CGPoint? = CGPoint(x: 201, y: 794.33),
    centrePoint: CGPoint? = CGPoint(x: 201, y: 794.33),
    userInteractionEnabled: Bool? = true
  ) -> [String: Any] {
    var node: [String: Any] = [
      FBAXWire.Node.label.rawValue: "Explore Grid Cell",
      FBAXWire.Node.identifier.rawValue: "media-thumbnail-cell",
      FBAXWire.Node.frame.rawValue: CGRectCreateDictionaryRepresentation(frame) as NSDictionary,
    ]
    if let isVisible {
      node[FBAXWire.Node.isVisible.rawValue] = isVisible
    }
    if let visiblePoint {
      node[FBAXWire.Node.visiblePoint.rawValue] = CGPointCreateDictionaryRepresentation(visiblePoint) as NSDictionary
    }
    if let centrePoint {
      node[FBAXWire.Node.centerPoint.rawValue] = CGPointCreateDictionaryRepresentation(centrePoint) as NSDictionary
    }
    if let userInteractionEnabled {
      node[FBAXWire.Node.userInteractionEnabled.rawValue] = userInteractionEnabled
    }
    return node
  }

  private static func interactable(_ node: [String: Any]) -> FBAccessibilityInteractable?? {
    FBAXTreeWalk.describeAllElements(
      fromTree: node, keys: [.interactable], nestedFormat: false, pid: 13515
    ).first?.interactable
  }

  // MARK: - Actionable

  // The point the accessibility server reports, not the frame centre — those coincide here.
  func testAnUnobstructedElementIsActionableAtItsReachablePoint() throws {
    let value = try XCTUnwrap(Self.interactable(Self.node()) ?? nil)
    XCTAssertEqual(value, .actionable(at: FBAccessibilityPoint(x: 201, y: 794.33)))
  }

  // MARK: - Blocked

  // The motivating case, with the numbers measured on a real Explore grid: the element is hittable, but
  // not at its centre, because the Liquid Glass tab bar covers the bottom of the cell. Every field
  // automation consults today — enabled, userInteractionEnabled, and hittability itself — says go ahead.
  func testAnElementWhoseCentreIsCoveredIsBlockedAsOccluded() throws {
    let value = try XCTUnwrap(
      Self.interactable(
        Self.node(visiblePoint: CGPoint(x: 201, y: 789.5), centrePoint: CGPoint(x: 201, y: 794.33))
      ) ?? nil
    )
    XCTAssertEqual(value, .blocked(reasons: [.occluded(by: nil)]))
  }

  // No reachable point at all. The `(-1, -1)` sentinel the runtime reports must not surface as a point.
  func testAnElementWithNoReachablePointIsBlockedAsNotHittable() throws {
    let value = try XCTUnwrap(
      Self.interactable(Self.node(isVisible: false, visiblePoint: CGPoint(x: -1, y: -1))) ?? nil
    )
    XCTAssertEqual(value, .blocked(reasons: [.notHittable]))
  }

  func testAViewThatTakesNoTouchesIsBlocked() throws {
    let value = try XCTUnwrap(Self.interactable(Self.node(userInteractionEnabled: false)) ?? nil)
    XCTAssertEqual(value, .blocked(reasons: [.userInteractionDisabled]))
  }

  func testAnElementWithNoAreaIsBlocked() throws {
    let value = try XCTUnwrap(
      Self.interactable(Self.node(frame: CGRect(x: 10, y: 20, width: 0, height: 44))) ?? nil
    )
    XCTAssertEqual(value, .blocked(reasons: [.zeroSize]))
  }

  // Reasons accumulate rather than short-circuit: a caller told only the first would fix it and hit the
  // next. Order is the order they are checked, which is what the encoding pins.
  func testEveryApplicableReasonIsReported() throws {
    let value = try XCTUnwrap(
      Self.interactable(
        Self.node(
          frame: CGRect(x: 10, y: 20, width: 0, height: 44),
          isVisible: false,
          visiblePoint: CGPoint(x: -1, y: -1),
          userInteractionEnabled: false
        )
      ) ?? nil
    )
    XCTAssertEqual(value, .blocked(reasons: [.zeroSize, .userInteractionDisabled, .notHittable]))
  }

  // MARK: - Cannot answer

  // A read that did not fetch the visibility attributes cannot judge interactability, and says so with an
  // explicit null rather than inventing a verdict from `enabled` — which is a hardcoded `true` on this
  // backend and the exact conflation this key exists to replace.
  func testABackendWithoutTheAttributesReportsNull() {
    let value = Self.interactable(Self.node(isVisible: nil, visiblePoint: nil, centrePoint: nil, userInteractionEnabled: nil))
    XCTAssertNotNil(value, "the key was requested, so it must be present")
    XCTAssertNil(value ?? nil, "and its value must be an explicit null")
  }

  // MARK: - Encoding

  // The union is internally tagged, so a consumer branches on `status` rather than probing for whichever
  // key happens to be present. These are the exact tokens a consumer matches on.
  func testActionableEncodesWithItsStatusAndPoint() throws {
    let encoded = try Self.encode(.actionable(at: FBAccessibilityPoint(x: 201, y: 789.5)))
    XCTAssertEqual(encoded["status"] as? String, "actionable")
    XCTAssertEqual((encoded["at"] as? [String: Any])?["x"] as? Double, 201)
    XCTAssertEqual((encoded["at"] as? [String: Any])?["y"] as? Double, 789.5)
    XCTAssertNil(encoded["reasons"], "the actionable case carries no reasons")
  }

  func testBlockedEncodesItsReasonKindsAndNoPoint() throws {
    let encoded = try Self.encode(.blocked(reasons: [.occluded(by: nil), .userInteractionDisabled]))
    XCTAssertEqual(encoded["status"] as? String, "blocked")
    XCTAssertNil(encoded["at"], "the blocked case carries no point")
    let reasons = try XCTUnwrap(encoded["reasons"] as? [[String: Any]])
    XCTAssertEqual(reasons.map { $0["kind"] as? String }, ["occluded", "user_interaction_disabled"])
    XCTAssertNil(reasons[0]["by"], "no occluder is named until a hit-test is paid for")
  }

  // Every reason's wire spelling, pinned — these are the tokens a consumer branches on, so a rename is a
  // silent break for anyone matching them.
  func testReasonWireSpellings() {
    let expected: [(FBAccessibilityInteractable.Reason, String)] = [
      (.notHittable, "not_hittable"),
      (.clippedByScreen, "clipped_by_screen"),
      (.occluded(by: nil), "occluded"),
      (.userInteractionDisabled, "user_interaction_disabled"),
      (.disabled, "disabled"),
      (.hidden, "hidden"),
      (.zeroSize, "zero_size"),
    ]
    for (reason, kind) in expected {
      XCTAssertEqual(reason.kind, kind)
    }
  }

  // MARK: - Clipped by the screen edge

  private static let screen = FBAccessibilityScreenInfo(width: 402, height: 874)

  /// Runs the post-serialization refinement the way `describeTree` does.
  private static func clipped(
    frame: CGRect,
    reasons: [FBAccessibilityInteractable.Reason] = [.notHittable]
  ) -> FBAccessibilityInteractable? {
    var element = FBAccessibilityDocumentElement()
    element.frame = .some(FBAccessibilityFrame(frame))
    element.interactable = .some(.blocked(reasons: reasons))
    return FBAXScreenBoundsClassifier.notingScreenClipping(element, screen: screen).interactable ?? nil
  }

  // The measured case: a row scrolled so its top is above the screen. Both facts are reported — it cannot
  // be reached, and the edge is cutting it off — because they license different recoveries.
  func testAnElementStraddlingTheTopEdgeIsNotedAsClipped() {
    XCTAssertEqual(
      Self.clipped(frame: CGRect(x: 16, y: -21.3, width: 370, height: 52)),
      .blocked(reasons: [.notHittable, .clippedByScreen]))
  }

  func testAnElementStraddlingTheBottomEdgeIsNotedAsClipped() {
    XCTAssertEqual(
      Self.clipped(frame: CGRect(x: 16, y: 850, width: 370, height: 52)),
      .blocked(reasons: [.notHittable, .clippedByScreen]))
  }

  func testAnElementStraddlingASideEdgeIsNotedAsClipped() {
    XCTAssertEqual(
      Self.clipped(frame: CGRect(x: -30, y: 400, width: 370, height: 52)),
      .blocked(reasons: [.notHittable, .clippedByScreen]))
  }

  // Wholly within the screen: whatever blocks it, the edge is not part of it.
  func testAnElementWithinTheScreenIsNotNotedAsClipped() {
    XCTAssertEqual(
      Self.clipped(frame: CGRect(x: 16, y: 400, width: 370, height: 52)),
      .blocked(reasons: [.notHittable]))
  }

  // Accumulates against whatever was already there rather than replacing it, and does not assume the
  // element is unreachable for a geometric reason — a disabled control clipped by the edge is both.
  func testClippingAccumulatesAgainstAnyOtherReason() {
    XCTAssertEqual(
      Self.clipped(frame: CGRect(x: 16, y: -10, width: 370, height: 52), reasons: [.userInteractionDisabled]),
      .blocked(reasons: [.userInteractionDisabled, .clippedByScreen])
    )
  }

  // Idempotent, so a refinement that runs twice cannot double the reason.
  func testClippingIsNotAddedTwice() {
    XCTAssertEqual(
      Self.clipped(frame: CGRect(x: 16, y: -10, width: 370, height: 52), reasons: [.notHittable, .clippedByScreen]),
      .blocked(reasons: [.notHittable, .clippedByScreen])
    )
  }

  // An actionable element is never annotated: it carries a reachable point and nothing else, so there is
  // no state in which a caller holds both a usable point and a complaint about the edge.
  func testAnActionableElementIsNeverNotedAsClipped() {
    var element = FBAccessibilityDocumentElement()
    element.frame = .some(FBAccessibilityFrame(CGRect(x: 16, y: -10, width: 370, height: 52)))
    element.interactable = .some(.actionable(at: FBAccessibilityPoint(x: 201, y: 20)))
    let refined: FBAccessibilityInteractable? =
      FBAXScreenBoundsClassifier.notingScreenClipping(element, screen: Self.screen).interactable ?? nil
    XCTAssertEqual(refined, FBAccessibilityInteractable.actionable(at: FBAccessibilityPoint(x: 201, y: 20)))
  }

  // MARK: - The `interactable` filter

  /// A two-element flat read: a reachable button and a covered one, both button-like.
  private static func mixedRead() -> [FBAccessibilityDocumentElement] {
    var reachable = FBAccessibilityDocumentElement()
    reachable.label = .some("StandBy")
    reachable.role = .some("AXButton")
    reachable.interactable = .some(.actionable(at: FBAccessibilityPoint(x: 201, y: 770)))
    var covered = FBAccessibilityDocumentElement()
    covered.label = .some("Screen Time")
    covered.role = .some("AXButton")
    covered.interactable = .some(.blocked(reasons: [.notHittable]))
    return [reachable, covered]
  }

  // The filter keeps what can actually be acted on. The covered button is button-like by every
  // structural measure — it has a label and an actionable role — and is dropped anyway, which is the
  // behaviour change: previously both of these survived.
  func testTheFilterKeepsOnlyElementsTheBackendReportsActionable() {
    let kept = FBAccessibilityElementFilter.interactable.apply(to: Self.mixedRead())
    XCTAssertEqual(kept.compactMap { $0.label ?? nil }, ["StandBy"])
  }

  // Where the backend returned no verdict, the structural heuristic still answers — so the flag degrades
  // in precision on the legacy path rather than reporting an empty screen.
  func testTheFilterFallsBackToTheHeuristicWhenTheBackendCannotAnswer() {
    var unjudged = FBAccessibilityDocumentElement()
    unjudged.label = .some("Screen Time")
    unjudged.role = .some("AXButton")
    unjudged.interactable = .some(nil)
    XCTAssertEqual(FBAccessibilityElementFilter.interactable.apply(to: [unjudged]).count, 1)

    var unlabelledContainer = FBAccessibilityDocumentElement()
    unlabelledContainer.interactable = .some(nil)
    XCTAssertTrue(
      FBAccessibilityElementFilter.interactable.apply(to: [unlabelledContainer]).isEmpty,
      "the fallback is the old heuristic, not keep-everything"
    )
  }

  // A verdict is never second-guessed by the heuristic: an element the backend judged blocked is dropped
  // even though its label and role would have carried it through the fallback.
  func testAVerdictIsNotOverriddenByTheHeuristic() {
    let covered = Self.mixedRead()[1]
    XCTAssertEqual(covered.label ?? nil, "Screen Time", "precondition: the labelled, button-role element")
    XCTAssertTrue(FBAccessibilityElementFilter.interactable.apply(to: [covered]).isEmpty)
  }

  // Requesting the filter is what puts the verdict on the wire; without this it would silently fall back
  // to the heuristic on every backend, having been given no verdict to match on.
  func testTheFilterRequestsTheVerdictItMatchesOn() {
    var options = FBAccessibilityRequestOptions()
    options.filter = .interactable
    XCTAssertTrue(options.serializationKeys.contains(.interactable))
    XCTAssertNotNil(FBAXWire.Node.fetchList(for: options.serializationKeys))
  }

  private static func encode(_ value: FBAccessibilityInteractable) throws -> [String: Any] {
    let data = try JSONEncoder().encode(value)
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }
}

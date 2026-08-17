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
    XCTAssertEqual(
      value, .blocked(reasons: [.zeroSize, .userInteractionDisabled, .notHittable]),
      "explanations keep their derivation order; the bare observation sorts last")
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
      .blocked(reasons: [.clippedByScreen, .notHittable]))
  }

  func testAnElementStraddlingTheBottomEdgeIsNotedAsClipped() {
    XCTAssertEqual(
      Self.clipped(frame: CGRect(x: 16, y: 850, width: 370, height: 52)),
      .blocked(reasons: [.clippedByScreen, .notHittable]))
  }

  func testAnElementStraddlingASideEdgeIsNotedAsClipped() {
    XCTAssertEqual(
      Self.clipped(frame: CGRect(x: -30, y: 400, width: 370, height: 52)),
      .blocked(reasons: [.clippedByScreen, .notHittable]))
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

  // Idempotent, so a refinement that runs twice cannot double the reason. The value is returned
  // untouched, ordering included — the ordering guarantee is applied at encode, so no construction or
  // early-return path can bypass it.
  func testClippingIsNotAddedTwice() {
    XCTAssertEqual(
      Self.clipped(frame: CGRect(x: 16, y: -10, width: 370, height: 52), reasons: [.notHittable, .clippedByScreen]),
      .blocked(reasons: [.notHittable, .clippedByScreen])
    )
  }

  // Whatever order a value was built in, the encoded form leads with an explanation.
  func testTheEncodedFormIsAlwaysOrderedMostSpecificFirst() throws {
    let encoded = try Self.encode(.blocked(reasons: [.notHittable, .clippedByScreen]))
    let reasons = try XCTUnwrap(encoded["reasons"] as? [[String: Any]])
    XCTAssertEqual(reasons.map { $0["kind"] as? String }, ["clipped_by_screen", "not_hittable"])
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

  // The whole point of the ordering: a consumer that reads only `reasons[0]` gets the most actionable
  // thing known, never the bare observation that explains nothing.
  func testTheBareObservationSortsBehindEveryExplanation() {
    let reasons: [FBAccessibilityInteractable.Reason] =
      [.notHittable, .clippedByScreen, .userInteractionDisabled]
    XCTAssertEqual(reasons.mostSpecificFirst, [.clippedByScreen, .userInteractionDisabled, .notHittable])
    XCTAssertFalse(reasons.mostSpecificFirst[0].isBareObservation)
  }

  // Ordering is a partition, not a sort, so explanations keep the order the checks derived them in.
  func testExplanationsKeepTheirDerivationOrder() {
    let reasons: [FBAccessibilityInteractable.Reason] =
      [.zeroSize, .notHittable, .hidden, .disabled]
    XCTAssertEqual(reasons.mostSpecificFirst, [.zeroSize, .hidden, .disabled, .notHittable])
  }

  // A lone bare observation is left alone — it is the commonest blocked shape, not a degenerate one.
  func testALoneObservationIsUnchanged() {
    XCTAssertEqual([FBAccessibilityInteractable.Reason.notHittable].mostSpecificFirst, [.notHittable])
  }

  // MARK: - Handled by a relative

  func testHandledByHasItsOwnWireSpelling() {
    XCTAssertEqual(FBAccessibilityInteractable.Reason.handledBy(nil).kind, "handled_by")
  }

  // Both cases that can name an element encode it under the same key, so a consumer reads `by` once
  // rather than once per reason kind.
  func testHandledByEncodesTheElementThatTookTheTouch() throws {
    let owner = FBAccessibilityElementRef(
      type: "Button", identifier: "standby", label: "StandBy",
      frame: FBAccessibilityFrame(CGRect(x: 16, y: 744, width: 370, height: 52)), pid: 3283
    )
    let encoded = try Self.encode(.blocked(reasons: [.handledBy(owner)]))
    let reasons = try XCTUnwrap(encoded["reasons"] as? [[String: Any]])
    XCTAssertEqual(reasons[0]["kind"] as? String, "handled_by")
    let by = try XCTUnwrap(reasons[0]["by"] as? [String: Any])
    XCTAssertEqual(by["label"] as? String, "StandBy")
    XCTAssertEqual(by["type"] as? String, "Button")
  }

  // Unnamed when no hit-test was paid for, the same as an unnamed occluder — the shape does not change,
  // only what is known.
  func testHandledByOmitsTheElementWhenNoHitTestWasPaidFor() throws {
    let encoded = try Self.encode(.blocked(reasons: [.handledBy(nil)]))
    let reasons = try XCTUnwrap(encoded["reasons"] as? [[String: Any]])
    XCTAssertEqual(reasons[0]["kind"] as? String, "handled_by")
    XCTAssertNil(reasons[0]["by"])
  }

  // It explains, so it sorts ahead of the bare observation like every other explanation.
  func testHandledByIsAnExplanationNotAnObservation() {
    XCTAssertFalse(FBAccessibilityInteractable.Reason.handledBy(nil).isBareObservation)
    XCTAssertEqual(
      [FBAccessibilityInteractable.Reason.notHittable, .handledBy(nil)].mostSpecificFirst,
      [.handledBy(nil), .notHittable]
    )
  }

  // An element explained by a relative is no longer unexplained, which is the whole point of adding it.
  func testAnElementHandledByARelativeIsNotUnexplained() throws {
    var handled = FBAccessibilityDocumentElement()
    handled.interactable = .some(.blocked(reasons: [.handledBy(nil)]))
    var bare = FBAccessibilityDocumentElement()
    bare.interactable = .some(.blocked(reasons: [.notHittable]))
    let summary = try XCTUnwrap(FBAccessibilityInteractionSummary(elements: [handled, bare]))
    XCTAssertEqual(summary.blocked, 2)
    XCTAssertEqual(summary.unexplained, 1)
  }

  // MARK: - What `occluded_by` needs serialized

  // `occluded_by` hit-tests an element's centre and then has to recognise whether the element that
  // answered is a relative of the target. Both halves need serialized fields it does not ask for: the
  // centre comes from the frame, and the recognition compares what the two reads can both see.
  //
  // Requesting it therefore implies all of them, which is what keeps the enrichment able to run and the
  // identity comparison symmetric.
  func testOccludedByImpliesTheKeysItsHitTestNeeds() {
    let keys = FBAccessibilityRequestOptions(keys: [.occludedBy]).serializationKeys
    XCTAssertTrue(keys.contains(.interactable), "the thing it enriches")
    XCTAssertTrue(keys.contains(.frameDict), "the frame its hit-test is aimed by")
    XCTAssertTrue(keys.contains(.uniqueID), "and the fields identity is compared on")
    XCTAssertTrue(keys.contains(.type))
    XCTAssertTrue(keys.contains(.label))
    XCTAssertTrue(keys.isSuperset(of: FBAXKeys.occluderIdentityKeys))
  }

  // MARK: - Explanatory power

  private static func element(_ value: FBAccessibilityInteractable?) -> FBAccessibilityDocumentElement {
    var element = FBAccessibilityDocumentElement()
    element.interactable = .some(value)
    return element
  }

  func testTheSummaryCountsVerdictsByOutcome() throws {
    let summary = try XCTUnwrap(
      FBAccessibilityInteractionSummary(elements: [
        Self.element(.actionable(at: FBAccessibilityPoint(x: 1, y: 2))),
        Self.element(.blocked(reasons: [.notHittable])),
        Self.element(.blocked(reasons: [.clippedByScreen, .notHittable])),
      ]))
    XCTAssertEqual(summary.actionable, 1)
    XCTAssertEqual(summary.blocked, 2)
  }

  // The number the whole summary exists for: only an element blocked with *nothing but* the bare
  // observation counts as unexplained. One that also carries a cause is explained, even though it still
  // carries the observation alongside.
  func testUnexplainedCountsOnlyElementsWithNoExplanationAtAll() throws {
    let summary = try XCTUnwrap(
      FBAccessibilityInteractionSummary(elements: [
        Self.element(.blocked(reasons: [.notHittable])),
        Self.element(.blocked(reasons: [.clippedByScreen, .notHittable])),
        Self.element(.blocked(reasons: [.userInteractionDisabled])),
      ]))
    XCTAssertEqual(summary.blocked, 3)
    XCTAssertEqual(summary.unexplained, 1, "only the bare-observation-only element is unexplained")
    XCTAssertEqual(try XCTUnwrap(summary.unexplainedRatio), 1.0 / 3.0, accuracy: 0.0001)
  }

  // Children are counted, not just roots — a nested read is the normal shape.
  func testTheSummaryCountsNestedElements() throws {
    var root = Self.element(.actionable(at: FBAccessibilityPoint(x: 1, y: 2)))
    root.children = [Self.element(.blocked(reasons: [.notHittable]))]
    let summary = try XCTUnwrap(FBAccessibilityInteractionSummary(elements: [root]))
    XCTAssertEqual(summary.actionable, 1)
    XCTAssertEqual(summary.unexplained, 1)
  }

  // Nil rather than zeroes when nothing carried a verdict, so a backend that cannot judge is not
  // mistaken for a screen with nothing blocked.
  func testTheSummaryIsAbsentWhenNothingCarriedAVerdict() {
    XCTAssertNil(FBAccessibilityInteractionSummary(elements: [Self.element(nil), Self.element(nil)]))
    XCTAssertNil(FBAccessibilityInteractionSummary(elements: []))
  }

  // No blocked elements means the ratio has no denominator, and reporting 0.0 would read as "perfectly
  // explained" rather than "nothing to explain".
  func testTheRatioIsAbsentWhenNothingIsBlocked() throws {
    let summary = try XCTUnwrap(
      FBAccessibilityInteractionSummary(
        elements: [Self.element(.actionable(at: FBAccessibilityPoint(x: 1, y: 2)))]
      ))
    XCTAssertEqual(summary.blocked, 0)
    XCTAssertNil(summary.unexplainedRatio)
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

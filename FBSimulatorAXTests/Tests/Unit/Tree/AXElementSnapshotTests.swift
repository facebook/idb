/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AppKit
@testable import FBSimulatorAX
@testable import FBSimulatorControl
import XCTest

final class AXElementSnapshotTests: XCTestCase {

  private static func element(label: String, children: [AXPMacPlatformElementDouble] = []) -> AXPMacPlatformElementDouble {
    AXPMacPlatformElementDouble(
      label: label, identifier: "\(label)-id", role: "AXButton", frame: NSRect(x: 1, y: 2, width: 3, height: 4),
      enabled: true, actionNames: nil, children: children)
  }

  // MARK: - Plans

  func testPlanForTheDefaultKeysNamesWhatTheSerializerConsumes() {
    let plan = AXReadPlan(keys: AXKeys.defaultSet, depth: .unlimited)
    XCTAssertEqual(
      plan.attributes,
      [.role, .label, .value, .identifier, .title, .help, .enabled, .customActions, .roleDescription, .subrole, .required, .traits])
  }

  func testTypeAloneStillPlansTheRole() {
    XCTAssertEqual(AXReadPlan(keys: [.type], depth: .unlimited).attributes, [.role])
  }

  func testInteractablePlansHittabilityAndItsExplanation() {
    XCTAssertEqual(AXReadPlan(keys: [.interactable], depth: .unlimited).attributes, [.hittability, .explainedBy])
  }

  func testOccludedByReadsWhatInteractableReads() {
    XCTAssertEqual(AXReadPlan(keys: [.occludedBy], depth: .unlimited).attributes, [.hittability, .explainedBy])
  }

  func testTheGuestFetchListFollowsThePlan() {
    XCTAssertNil(AXWire.Node.fetchList(for: AXReadPlan(keys: [.traits], depth: .unlimited)), "the default list fetches traits")
    XCTAssertEqual(
      AXWire.Node.fetchList(for: AXReadPlan(keys: [.label], depth: .unlimited)),
      AXWire.Node.defaultFetchList.filter { $0 != AXWire.Node.xcTraits.rawValue },
      "a plan without traits drops the bitmask")
    XCTAssertEqual(
      AXWire.Node.fetchList(for: AXReadPlan(keys: [.traits, .interactable], depth: .unlimited)),
      AXWire.Node.defaultFetchList + AXWire.Node.interactableAttributes.map(\.rawValue),
      "a plan reading hittability fetches what it is derived from")
  }

  func testKeysAnsweredWithoutAReadPlanNothing() {
    XCTAssertEqual(AXReadPlan(keys: [.frame, .frameDict, .pid, .isRemote], depth: .unlimited).attributes, [])
  }

  func testDepthCountsDownToTheLastLevel() {
    XCTAssertEqual(AXReadPlan.Depth.unlimited.descendant, .unlimited)
    XCTAssertEqual(AXReadPlan.Depth.limited(2).descendant, .limited(1))
    XCTAssertNil(AXReadPlan.Depth.limited(0).descendant)
  }

  // MARK: - Reading

  func testABatchedReadRequestsThePlannedAttributesInOneRequest() {
    let child = Self.element(label: "child")
    let root = Self.element(label: "root", children: [child])
    let snapshot = AXElementSnapshot.read(root, plan: AXReadPlan(attributes: [.label, .role], depth: .unlimited), token: "t")

    XCTAssertEqual(snapshot.label, "root")
    XCTAssertEqual(snapshot.role, "AXButton")
    XCTAssertEqual(snapshot.frame, NSRect(x: 1, y: 2, width: 3, height: 4))
    XCTAssertEqual(snapshot.children.map(\.label), ["child"])
    XCTAssertEqual(root.multipleAttributeRequests.map(Set.init), [["AXFrame", "AXDescription", "AXRole", "AXChildren"]])
    XCTAssertEqual(
      root.accessedProperties as? Set<String>, ["accessibilityMultipleAttributes", "translation"],
      "no single accessor is read")
    XCTAssertEqual(child.multipleAttributeRequests.count, 1, "each element is one request")
  }

  func testABatchedReadAtItsLastLevelDoesNotAskForChildren() {
    let element = Self.element(label: "root")
    _ = AXElementSnapshot.read(element, plan: AXReadPlan(attributes: [], depth: .limited(0)), token: "")
    XCTAssertEqual(element.multipleAttributeRequests, [["AXFrame"]])
  }

  func testBatchedAndPerAttributeReadsAgree() {
    func tree() -> AXPMacPlatformElementDouble {
      Self.element(label: "root", children: [Self.element(label: "a"), Self.element(label: "b")])
    }
    let plan = AXReadPlan(keys: AXKeys.defaultSet, depth: .unlimited)
    let serialization = AXSerialization(keys: AXKeys.defaultSet, nested: true)
    let batched = AXElementSnapshot.read(tree(), plan: plan, token: "", mode: .batched)
    let perAttribute = AXElementSnapshot.read(tree(), plan: plan, token: "", mode: .perAttribute)
    XCTAssertEqual(
      AXNodeSerializer.recursiveDescription(fromSnapshot: batched, serialization: serialization, collector: nil, seenPids: nil),
      AXNodeSerializer.recursiveDescription(fromSnapshot: perAttribute, serialization: serialization, collector: nil, seenPids: nil))
  }

  func testAPerAttributeReadFetchesOnlyThePlannedAttributesAndTheFrame() {
    let element = Self.element(label: "root")
    let snapshot = AXElementSnapshot.read(
      element, plan: AXReadPlan(attributes: [.label], depth: .limited(0)), token: "t", mode: .perAttribute)

    XCTAssertEqual(snapshot.label, "root")
    XCTAssertEqual(snapshot.frame, NSRect(x: 1, y: 2, width: 3, height: 4))
    XCTAssertNil(snapshot.identifier, "an unplanned attribute is not read")
    XCTAssertEqual(
      element.accessedProperties as? Set<String>,
      ["translation", "accessibilityFrame", "accessibilityLabel"],
      "the token and pid come from the translation; nothing beyond the plan is fetched")
  }

  func testReadSetsTheTokenOnEveryElementItReads() {
    let child = Self.element(label: "child")
    let root = Self.element(label: "root", children: [child])
    _ = AXElementSnapshot.read(root, plan: AXReadPlan(attributes: [], depth: .unlimited), token: "the-token")

    XCTAssertEqual(root.translation.bridgeDelegateToken, "the-token")
    XCTAssertEqual(child.translation.bridgeDelegateToken, "the-token")
  }

  func testReadDescendsToThePlannedDepthAndNoFurther() {
    let grandchild = Self.element(label: "grandchild")
    let child = Self.element(label: "child", children: [grandchild])
    let root = Self.element(label: "root", children: [child])

    let snapshot = AXElementSnapshot.read(
      root, plan: AXReadPlan(attributes: [.label], depth: .limited(1)), token: "", mode: .perAttribute)

    XCTAssertEqual(snapshot.children.map(\.label), ["child"])
    XCTAssertEqual(snapshot.children.first?.children.count, 0, "the plan stops one level down")
    XCTAssertFalse(
      (child.accessedProperties as? Set<String>)?.contains("accessibilityChildren") ?? true,
      "the last planned level does not ask for children it will not read")
    XCTAssertTrue(grandchild.accessedProperties.count == 0, "nothing below the planned depth is touched")
  }

  func testHittabilityAndItsExplanationFetchNothingOnTheTranslator() {
    let element = Self.element(label: "root")
    let snapshot = AXElementSnapshot.read(
      element, plan: AXReadPlan(attributes: [.hittability, .explainedBy], depth: .limited(0)), token: "")

    XCTAssertNil(snapshot.hittability)
    XCTAssertNil(snapshot.explainedBy)
    XCTAssertEqual(element.multipleAttributeRequests, [["AXFrame"]], "the translator has nothing to fetch for either")
  }
}

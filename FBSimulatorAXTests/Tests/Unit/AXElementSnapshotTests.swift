/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AppKit
@testable import FBSimulatorAX
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

  func testKeysAnsweredWithoutAReadPlanNothing() {
    XCTAssertEqual(AXReadPlan(keys: [.frame, .frameDict, .pid, .isRemote], depth: .unlimited).attributes, [])
  }

  func testDepthCountsDownToTheLastLevel() {
    XCTAssertEqual(AXReadPlan.Depth.unlimited.descendant, .unlimited)
    XCTAssertEqual(AXReadPlan.Depth.limited(2).descendant, .limited(1))
    XCTAssertNil(AXReadPlan.Depth.limited(0).descendant)
  }

  // MARK: - Reading

  func testReadFetchesOnlyThePlannedAttributesAndTheFrame() {
    let element = Self.element(label: "root")
    let snapshot = AXElementSnapshot.read(element, plan: AXReadPlan(attributes: [.label], depth: .limited(0)), token: "t")

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

    let snapshot = AXElementSnapshot.read(root, plan: AXReadPlan(attributes: [.label], depth: .limited(1)), token: "")

    XCTAssertEqual(snapshot.children.map(\.label), ["child"])
    XCTAssertEqual(snapshot.children.first?.children.count, 0, "the plan stops one level down")
    XCTAssertFalse(
      (child.accessedProperties as? Set<String>)?.contains("accessibilityChildren") ?? true,
      "the last planned level does not ask for children it will not read")
    XCTAssertTrue(grandchild.accessedProperties.count == 0, "nothing below the planned depth is touched")
  }

  func testHittabilityFetchesNothingFurtherWhenTheBackendCannotAnswer() {
    let element = Self.element(label: "root")
    let snapshot = AXElementSnapshot.read(
      element, plan: AXReadPlan(attributes: [.hittability], depth: .limited(0)), token: "")

    XCTAssertNil(snapshot.hittability)
    XCTAssertEqual(
      element.accessedProperties as? Set<String>, ["translation", "accessibilityFrame"],
      "hidden and enabled are read only to explain a hittability the backend reported")
  }
}

/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import FBControlCore
@testable import FBSimulatorControl
import Foundation
import XCTest
import XCTestBootstrap

/// A fake `RemoteInvoking` returning a single canned element and its attributes, so the remote
/// point-describe schema reproduction can be exercised without a live DTX connection.
private actor FakeReadInvoker: RemoteInvoking {

  private let stringAttributes: [String: String]
  private let frame: CGRect?
  private let returnsElement: Bool

  init(stringAttributes: [String: String], frame: CGRect?, returnsElement: Bool = true) {
    self.stringAttributes = stringAttributes
    self.frame = frame
    self.returnsElement = returnsElement
  }

  func beginSession(clientProtocolVersion: Int, deadline: TimeInterval) async throws {}
  func exchangeCapabilities(deadline: TimeInterval) async throws -> sending Any? { NSDictionary() }
  func loadAccessibility(timeout: TimeInterval, deadline: TimeInterval) async throws {}
  func synthesizeEvent(_ record: sending Any, implicitConfirmationInterval: TimeInterval, deadline: TimeInterval) async throws {}

  func requestElement(atPoint point: sending Any, deadline: TimeInterval) async throws -> sending Any? {
    returnsElement ? ("element" as NSString) : nil
  }

  func fetchAttributes(_ attributes: sending Any, forElement element: sending Any, deadline: TimeInterval) async throws -> sending Any? {
    var dict: [String: Any] = stringAttributes
    if let frame {
      dict[FBRemoteAutomationAXAttribute.frame] = CGRectCreateDictionaryRepresentation(frame)
    }
    return dict as NSDictionary
  }
}

final class FBRemoteAutomationDescribeTests: XCTestCase {

  func testPointDescribeReproducesSchema() async throws {
    let invoker = FakeReadInvoker(
      stringAttributes: [
        FBRemoteAutomationAXAttribute.label: "General",
        FBRemoteAutomationAXAttribute.value: "On",
        FBRemoteAutomationAXAttribute.identifier: "com.apple.settings.general",
        FBRemoteAutomationAXAttribute.automationType: "Button",
      ],
      frame: CGRect(x: 16, y: 380, width: 370, height: 52)
    )
    let session = FBRemoteAutomationSession(invoker: invoker, processIdentifier: 0)

    let dict = try await FBSimulatorRemoteAutomation.describeElement(
      atX: 200, y: 406, using: session, keys: FBAXKeys.defaultSet
    )

    XCTAssertEqual(dict[FBAXKeys.label.rawValue] as? String, "General")
    XCTAssertEqual(dict[FBAXKeys.value.rawValue] as? String, "On")
    XCTAssertEqual(dict[FBAXKeys.uniqueID.rawValue] as? String, "com.apple.settings.general")
    XCTAssertEqual(dict[FBAXKeys.role.rawValue] as? String, "Button")
    XCTAssertEqual(dict[FBAXKeys.type.rawValue] as? String, "Button")
    // Frame is emitted both as the AXFrame rect string and the frame dictionary.
    XCTAssertNotNil(dict[FBAXKeys.frame.rawValue] as? String)
    let frameDict = try XCTUnwrap(dict[FBAXKeys.frameDict.rawValue] as? [String: Any])
    XCTAssertFalse(frameDict.isEmpty)
  }

  func testPointDescribeThrowsWhenNoElement() async throws {
    let invoker = FakeReadInvoker(stringAttributes: [:], frame: nil, returnsElement: false)
    let session = FBRemoteAutomationSession(invoker: invoker, processIdentifier: 0)

    do {
      _ = try await FBSimulatorRemoteAutomation.describeElement(
        atX: 1, y: 1, using: session, keys: FBAXKeys.defaultSet
      )
      XCTFail("Expected describeElement to throw when no element is found")
    } catch {
      // expected
    }
  }

  private static func sampleTree() -> [String: Any] {
    [
      FBRemoteAutomationAXAttribute.label: "root",
      FBRemoteAutomationAXAttribute.children: [
        [
          FBRemoteAutomationAXAttribute.label: "child",
          FBRemoteAutomationAXAttribute.children: [[String: Any]](),
        ] as [String: Any]
      ],
    ]
  }

  func testDescribeAllFlattensTree() {
    let elements = FBSimulatorRemoteAutomation.describeAllElements(
      fromTree: Self.sampleTree(), keys: FBAXKeys.defaultSet, nestedFormat: false, pid: 0
    )
    XCTAssertEqual(elements.count, 2)
    let labels = elements.compactMap { $0[FBAXKeys.label.rawValue] as? String }
    XCTAssertTrue(labels.contains("root"))
    XCTAssertTrue(labels.contains("child"))
  }

  func testDescribeAllNestedEmbedsChildren() throws {
    let elements = FBSimulatorRemoteAutomation.describeAllElements(
      fromTree: Self.sampleTree(), keys: FBAXKeys.defaultSet, nestedFormat: true, pid: 0
    )
    XCTAssertEqual(elements.count, 1)
    XCTAssertEqual(elements[0][FBAXKeys.label.rawValue] as? String, "root")
    let children = try XCTUnwrap(elements[0]["children"] as? [[String: Any]])
    XCTAssertEqual(children.count, 1)
    XCTAssertEqual(children[0][FBAXKeys.label.rawValue] as? String, "child")
  }

  func testBuildPlatformElementTreeTagsEveryNodeWithPid() {
    let root = FBSimulatorRemoteAutomation.buildPlatformElementTree(from: Self.sampleTree(), pid: 99)
    XCTAssertEqual(root.axTranslationPid, 99)
    XCTAssertEqual(root.axChildren().first?.axTranslationPid, 99)
  }

  func testFrameCenterFindsMatchingElement() {
    let elements: [[String: Any]] = [
      [FBAXKeys.label.rawValue: "Other", FBAXKeys.frameDict.rawValue: ["x": 0.0, "y": 0.0, "width": 10.0, "height": 10.0]],
      [FBAXKeys.label.rawValue: "General", FBAXKeys.frameDict.rawValue: ["x": 16.0, "y": 380.0, "width": 370.0, "height": 52.0]],
    ]
    let center = FBSimulatorRemoteAutomation.frameCenter(inElements: elements, markerValue: "General", key: .label)
    XCTAssertEqual(center?.x ?? -1, 201, accuracy: 0.001)
    XCTAssertEqual(center?.y ?? -1, 406, accuracy: 0.001)
  }

  func testFrameCenterReturnsNilWhenNoMatch() {
    XCTAssertNil(FBSimulatorRemoteAutomation.frameCenter(inElements: [], markerValue: "General", key: .label))
  }
}

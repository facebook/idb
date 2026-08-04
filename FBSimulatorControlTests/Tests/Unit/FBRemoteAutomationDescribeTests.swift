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

/// A stand-in for the daemon's `XCAccessibilityElement`. The point-read owning pid is read off the
/// returned element via an `@objc processIdentifier` message (the session `unsafeBitCast`s the handle
/// to a module-local protocol), so the fake element must answer that selector.
private final class FakeAXElement: NSObject {
  @objc let processIdentifier: CInt
  init(processIdentifier: CInt) { self.processIdentifier = processIdentifier }
}

/// A fake `RemoteInvoking` returning a single canned element and its attributes, so the remote
/// point-describe schema reproduction can be exercised without a live DTX connection.
private actor FakeReadInvoker: RemoteInvoking {

  private let stringAttributes: [String: String]
  private let frame: CGRect?
  private let returnsElement: Bool
  private let pid: CInt

  init(stringAttributes: [String: String], frame: CGRect?, returnsElement: Bool = true, pid: CInt = 1320) {
    self.stringAttributes = stringAttributes
    self.frame = frame
    self.returnsElement = returnsElement
    self.pid = pid
  }

  func beginSession(clientProtocolVersion: Int, deadline: TimeInterval) async throws {}
  func exchangeCapabilities(deadline: TimeInterval) async throws -> sending Any? { NSDictionary() }
  func loadAccessibility(timeout: TimeInterval, deadline: TimeInterval) async throws {}
  func synthesizeEvent(_ record: sending Any, implicitConfirmationInterval: TimeInterval, deadline: TimeInterval) async throws {}

  func requestElement(atPoint point: sending Any, deadline: TimeInterval) async throws -> sending Any? {
    returnsElement ? FakeAXElement(processIdentifier: pid) : nil
  }

  func fetchAttributes(_ attributes: sending Any, forElement element: sending Any, deadline: TimeInterval) async throws -> sending Any? {
    var dict: [String: Any] = stringAttributes
    if let frame {
      dict[FBAXWire.Node.frame.rawValue] = CGRectCreateDictionaryRepresentation(frame)
    }
    return dict as NSDictionary
  }

  func setAttribute(_ attribute: sending Any, value: sending Any, forElement element: sending Any, deadline: TimeInterval) async throws {}
}

final class FBRemoteAutomationDescribeTests: XCTestCase {

  func testPointDescribeReproducesSchema() async throws {
    let invoker = FakeReadInvoker(
      stringAttributes: [
        FBAXWire.Node.label.rawValue: "General",
        FBAXWire.Node.value.rawValue: "On",
        FBAXWire.Node.identifier.rawValue: "com.apple.settings.general",
        FBAXWire.Node.automationType.rawValue: "Button",
      ],
      frame: CGRect(x: 16, y: 380, width: 370, height: 52)
    )
    let session = try await FBRemoteAutomationSession.connected(invoker: invoker, processIdentifier: 0)

    let hit = try await FBSimulatorRemoteAutomation.hitTestElement(
      atX: 200, y: 406, using: session, keys: FBAXKeys.defaultSet
    )
    let value = try XCTUnwrap(hit)
    let dict = try XCTUnwrap(value.toFoundationObject() as? [String: Any])

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

  func testPointHitTestReturnsNilWhenNoElement() async throws {
    let invoker = FakeReadInvoker(stringAttributes: [:], frame: nil, returnsElement: false)
    let session = try await FBRemoteAutomationSession.connected(invoker: invoker, processIdentifier: 0)

    // No element at the point is a valid empty hit-test result: nil, not a thrown error. The public
    // describe(.point) turns this nil into a noElementAtPoint error (carrying the accessibility hint),
    // preserving that contract; the targeted hit-test itself distinguishes empty from failure.
    let value = try await FBSimulatorRemoteAutomation.hitTestElement(
      atX: 1, y: 1, using: session, keys: FBAXKeys.defaultSet
    )
    XCTAssertNil(value)
  }

  func testPointHitTestTagsTheElementWithItsOwningPid() async throws {
    // The point read must carry the pid of the process that owns the hit element, not a placeholder,
    // so a serialized point element reports the same owning pid as the whole-tree read does.
    let invoker = FakeReadInvoker(
      stringAttributes: [FBAXWire.Node.label.rawValue: "General"],
      frame: CGRect(x: 16, y: 380, width: 370, height: 52),
      pid: 4321
    )
    let session = try await FBRemoteAutomationSession.connected(invoker: invoker, processIdentifier: 0)

    let hit = try await FBSimulatorRemoteAutomation.hitTestElement(
      atX: 200, y: 406, using: session, keys: FBAXKeys.defaultSet
    )
    let dict = try XCTUnwrap(try XCTUnwrap(hit).toFoundationObject() as? [String: Any])
    XCTAssertEqual((dict[FBAXKeys.pid.rawValue] as? NSNumber)?.intValue, 4321)
  }

  private static func sampleTree() -> [String: Any] {
    [
      FBAXWire.Node.label.rawValue: "root",
      FBAXWire.Node.children.rawValue: [
        [
          FBAXWire.Node.label.rawValue: "child",
          FBAXWire.Node.children.rawValue: [[String: Any]](),
        ] as [String: Any]
      ],
    ]
  }

  func testDescribeAllFlattensTree() {
    let elements = FBAXTreeSerialization.describeAllElements(
      fromTree: Self.sampleTree(), keys: FBAXKeys.defaultSet, nestedFormat: false, pid: 0
    )
    XCTAssertEqual(elements.count, 2)
    let labels = elements.compactMap { ($0.toFoundationObject() as? [String: Any])?[FBAXKeys.label.rawValue] as? String }
    XCTAssertTrue(labels.contains("root"))
    XCTAssertTrue(labels.contains("child"))
  }

  func testDescribeAllNestedEmbedsChildren() throws {
    let elements = FBAXTreeSerialization.describeAllElements(
      fromTree: Self.sampleTree(), keys: FBAXKeys.defaultSet, nestedFormat: true, pid: 0
    )
    XCTAssertEqual(elements.count, 1)
    let root = try XCTUnwrap(elements[0].toFoundationObject() as? [String: Any])
    XCTAssertEqual(root[FBAXKeys.label.rawValue] as? String, "root")
    let children = try XCTUnwrap(root["children"] as? [[String: Any]])
    XCTAssertEqual(children.count, 1)
    XCTAssertEqual(children[0][FBAXKeys.label.rawValue] as? String, "child")
  }

  func testBuildPlatformElementTreeTagsEveryNodeWithPid() {
    let root = FBAXTreeSerialization.buildPlatformElementTree(from: Self.sampleTree(), pid: 99)
    XCTAssertEqual(root.axTranslationPid, 99)
    XCTAssertEqual(root.axChildren().first?.axTranslationPid, 99)
  }

  func testFrameCenterFindsMatchingElement() {
    let elements: [FBJSONValue] = [
      FBJSONValue(foundation: [FBAXKeys.label.rawValue: "Other", FBAXKeys.frameDict.rawValue: ["x": 0.0, "y": 0.0, "width": 10.0, "height": 10.0]]),
      FBJSONValue(foundation: [FBAXKeys.label.rawValue: "General", FBAXKeys.frameDict.rawValue: ["x": 16.0, "y": 380.0, "width": 370.0, "height": 52.0]]),
    ]
    let center = FBAXTreeSerialization.frameCenter(inElements: elements, markerValue: "General", key: .label)
    XCTAssertEqual(center?.x ?? -1, 201, accuracy: 0.001)
    XCTAssertEqual(center?.y ?? -1, 406, accuracy: 0.001)
  }

  func testFrameCenterReturnsNilWhenNoMatch() {
    XCTAssertNil(FBAXTreeSerialization.frameCenter(inElements: [], markerValue: "General", key: .label))
  }

  func testMatchingElementFindsByMarker() {
    let elements: [FBJSONValue] = [
      FBJSONValue(foundation: [FBAXKeys.label.rawValue: "Other"]),
      FBJSONValue(foundation: [FBAXKeys.label.rawValue: "General", FBAXKeys.uniqueID.rawValue: "com.apple.settings.general"]),
    ]
    let match = FBAXTreeSerialization.matchingElement(inElements: elements, markerValue: "General", key: .label)
    let matchDict = match?.toFoundationObject() as? [String: Any]
    XCTAssertEqual(matchDict?[FBAXKeys.uniqueID.rawValue] as? String, "com.apple.settings.general")
    XCTAssertNil(FBAXTreeSerialization.matchingElement(inElements: elements, markerValue: "Nope", key: .label))
  }

  func testResolveMarkerResolvesAMatchThatHasAFrame() {
    let elements: [FBJSONValue] = [
      FBJSONValue(foundation: [FBAXKeys.label.rawValue: "General", FBAXKeys.frameDict.rawValue: ["x": 16.0, "y": 380.0, "width": 370.0, "height": 52.0]])
    ]
    XCTAssertEqual(
      FBAXTreeSerialization.resolveMarker(inElements: elements, markerValue: "General", key: .label),
      .resolved(x: 201, y: 406)
    )
  }

  func testResolveMarkerReportsOffScreenForAFramelessMatch() {
    // The element matches the marker but carries no frame dictionary (off-screen or still settling),
    // so there is no point to tap — distinct from the marker matching nothing.
    let elements: [FBJSONValue] = [
      FBJSONValue(foundation: [FBAXKeys.label.rawValue: "General"])
    ]
    XCTAssertEqual(
      FBAXTreeSerialization.resolveMarker(inElements: elements, markerValue: "General", key: .label),
      .offScreen
    )
  }

  func testResolveMarkerReportsNotFoundWhenNoMatch() {
    let elements: [FBJSONValue] = [
      FBJSONValue(foundation: [FBAXKeys.label.rawValue: "Other", FBAXKeys.frameDict.rawValue: ["x": 0.0, "y": 0.0, "width": 10.0, "height": 10.0]])
    ]
    XCTAssertEqual(
      FBAXTreeSerialization.resolveMarker(inElements: elements, markerValue: "General", key: .label),
      .notFound
    )
  }

  func testResolveMarkerPrefersAMatchWithAFrameOverAFramelessOne() {
    // A frameless match must not mask a later on-screen match: the resolution is the framed element.
    let elements: [FBJSONValue] = [
      FBJSONValue(foundation: [FBAXKeys.label.rawValue: "General"]),
      FBJSONValue(foundation: [FBAXKeys.label.rawValue: "General", FBAXKeys.frameDict.rawValue: ["x": 16.0, "y": 380.0, "width": 370.0, "height": 52.0]]),
    ]
    XCTAssertEqual(
      FBAXTreeSerialization.resolveMarker(inElements: elements, markerValue: "General", key: .label),
      .resolved(x: 201, y: 406)
    )
  }

  func testPollUntilFoundReturnsWhenProbeSucceeds() async throws {
    final class Counter { var n = 0 }
    let counter = Counter()
    let result = try await FBUIAutomationPolling.pollUntilFound(
      timeout: 10, pollInterval: 0.01, clock: { 0 }, sleep: { _ in }
    ) { () -> Int? in
      counter.n += 1
      return counter.n >= 2 ? 42 : nil
    }
    XCTAssertEqual(result, 42)
    XCTAssertEqual(counter.n, 2)
  }

  func testPollUntilFoundTimesOut() async throws {
    final class Clock { var t = 0.0 }
    let clock = Clock()
    let result: Int? = try await FBUIAutomationPolling.pollUntilFound(
      timeout: 1, pollInterval: 0.01, clock: { clock.t }, sleep: { _ in clock.t += 0.6 }
    ) { nil }
    XCTAssertNil(result)
  }

  func testRemoteTapRejectsAValueAssertion() {
    // The remote backend can't read-and-assert an element's value before tapping, so an expectedValue
    // must surface as unsupported rather than a silent no-assertion tap.
    XCTAssertThrowsError(try FBSimulatorRemoteAutomation.rejectValueAssertion("On")) { error in
      guard case let FBUIAutomationError.operationUnsupported(backend, operation) = error else {
        return XCTFail("Expected operationUnsupported, got \(error)")
      }
      if case .remoteAutomation = backend {
      } else {
        XCTFail("Expected the remoteAutomation backend, got \(backend)")
      }
      XCTAssertTrue(operation.contains("expected value"), "Operation should name the value assertion, got \"\(operation)\"")
    }
    XCTAssertNoThrow(try FBSimulatorRemoteAutomation.rejectValueAssertion(nil))
  }

  func testWaitForMarkerRejectsANegativePollInterval() async {
    // A negative interval traps the real sleep timer's unsigned conversion; the wait must reject it
    // before any polling begins rather than crash.
    final class Probed { var ran = false }
    let probed = Probed()
    do {
      try await FBUIAutomationPolling.waitForMarker(
        .marker(value: "General", key: .label, depth: 0),
        backend: .remoteAutomation,
        timeout: 10,
        pollInterval: -1
      ) { _, _, _ in
        probed.ran = true
        return true
      }
      XCTFail("Expected waitForMarker to reject a negative poll interval")
    } catch let FBUIAutomationError.invalidPollInterval(backend, pollInterval) {
      if case .remoteAutomation = backend {
      } else {
        XCTFail("Expected the remoteAutomation backend, got \(backend)")
      }
      XCTAssertEqual(pollInterval, -1, accuracy: 0.0001)
    } catch {
      XCTFail("Expected invalidPollInterval, got \(error)")
    }
    XCTAssertFalse(probed.ran, "The probe must not run when the poll interval is rejected")
  }
}

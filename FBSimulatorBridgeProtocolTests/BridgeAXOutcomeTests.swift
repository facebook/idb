/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorBridgeProtocol
import Foundation
import Testing

// What the guest writes for each verb is pinned in SimulatorFrameworkBridgeLibTests'
// AccessibilityWireContractTests, which decode the guest's own frames with these types. These tests pin the rules
// the types themselves add, and decode one frame captured from a real simulator.
@Suite
struct BridgeAXOutcomeTests {
  /// A `describe` of the Settings root on an iPhone simulator: 164 elements, as the guest sent it.
  private static func settingsRead() throws -> Data {
    let fixture = try #require(
      Bundle(for: BundleFinder.self).url(forResource: "ax-describe-settings", withExtension: "json"))
    return try Data(contentsOf: fixture)
  }

  private func decode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
    try JSONDecoder().decode(type, from: Data(json.utf8))
  }

  private func roundTrip<Value: Codable & Equatable>(_ value: Value) throws -> Value {
    try JSONDecoder().decode(Value.self, from: JSONEncoder().encode(value))
  }

  private func jsonObject(_ data: Data) throws -> NSDictionary {
    try #require(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
  }

  private func count(_ node: BridgeAXNode) -> Int {
    1 + (node.children ?? []).map(count).reduce(0, +)
  }

  // MARK: - A real read

  @Test
  func aSettingsReadDecodesIntoATypedTree() throws {
    let answer = try JSONDecoder().decode(BridgeAXAnswer.self, from: Self.settingsRead())
    guard case let .tree(read) = answer else {
      Issue.record("expected a tree, got \(answer)")
      return
    }
    #expect(read.pid == 69447)
    #expect(!read.truncated)
    #expect(read.method == .windowServer)
    #expect(read.automation == BridgeAXAutomationState(enabled: true, asserted: false))
    #expect(read.phases?.machRoundTrips == 1)
    #expect(count(read.tree) == 164)
    #expect(read.tree.label == .string("Settings"))
  }

  @Test
  func aSettingsReadReencodesAsTheFrameTheGuestSent() throws {
    let data = try Self.settingsRead()
    let answer = try JSONDecoder().decode(BridgeAXAnswer.self, from: data)
    #expect(try jsonObject(JSONEncoder().encode(answer)) == jsonObject(data))
  }

  // MARK: - Nodes

  @Test
  func anAttributeTheServerCouldNotAnswerReadsAsAbsent() throws {
    let node = try decode(BridgeAXNode.self, #"{"XC_kAXXCAttributeLabel":null,"XC_kAXXCAttributeFrame":null}"#)
    #expect(node == BridgeAXNode())
  }

  @Test
  func aNodeWithNothingReadCarriesNothing() throws {
    #expect(try jsonObject(JSONEncoder().encode(BridgeAXNode())) == [:])
  }

  @Test
  func aNodeRoundTripsThroughItsOwnEncoding() throws {
    var explanation = BridgeAXNode()
    explanation.elementType = .string("SBAlertItemWindow")
    var node = BridgeAXNode()
    node.elementType = .integer(9)
    node.elementBaseType = .string("UIButton")
    node.label = .string("Done")
    node.value = .number(0.5)
    node.identifier = .string("done")
    node.frame = BridgeAXRect(x: 10, y: 20.5, width: 100, height: nil)
    node.automationType = .integer(9)
    node.xcTraits = 1
    node.children = []
    node.windowDisplayID = 3
    node.isVisible = false
    node.visiblePoint = BridgeAXPoint(x: -1, y: -1)
    node.centerPoint = BridgeAXPoint(x: 60, y: 45)
    node.userInteractionEnabled = true
    node.isEnabled = true
    node.translatorRole = 4
    node.translatorSubrole = 12
    node.traits = 9_007_199_254_740_993
    node.elementIdentity = 105_553_116_266_496
    node.attributeReadFailures = ["XC_kAXXCAttributeValue": "timed out"]
    node.explainedBy = explanation
    #expect(try roundTrip(node) == node)
  }

  @Test
  func aScalarKeepsTheKindItArrivedAs() throws {
    #expect(try decode([BridgeAXScalar].self, #"["9",9,9.5,true]"#) == [.string("9"), .integer(9), .number(9.5), .bool(true)])
    let scalars: [BridgeAXScalar] = [.string("9"), .integer(-9), .number(9.5), .bool(false)]
    #expect(try roundTrip(scalars) == scalars)
  }

  @Test
  func aNonFiniteCoordinateIsLeftOut() throws {
    let rect = BridgeAXRect(x: .infinity, y: 0, width: .nan, height: nil)
    #expect(try jsonObject(JSONEncoder().encode(rect)) == ["Y": 0])
    #expect(try roundTrip(rect) == BridgeAXRect(x: nil, y: 0, width: nil, height: nil))
  }

  // MARK: - Outcomes

  // MARK: - Answers

  @Test
  func everyAnswerEncodesAsItsCase() throws {
    func text(_ answer: BridgeAXAnswer) throws -> String {
      let encoder = JSONEncoder()
      encoder.outputFormatting = .sortedKeys
      return String(decoding: try encoder.encode(answer), as: UTF8.self)
    }
    var node = BridgeAXNode()
    node.label = .string("OK")
    let cases: [(BridgeAXAnswer, String)] = [
      (.tree(BridgeAXTreeResponse(tree: node, pid: 3, truncated: false)), #"{"tree":{"response":{"pid":3,"tree":{"XC_kAXXCAttributeLabel":"OK"},"truncated":false}}}"#),
      (.hitTest(.element(node, pid: 3)), #"{"hitTest":{"response":{"element":{"pid":3,"tree":{"XC_kAXXCAttributeLabel":"OK"}}}}}"#),
      (.hitTest(.empty), #"{"hitTest":{"response":{"empty":{}}}}"#),
      (.write(.written(pid: 3)), #"{"write":{"response":{"written":{"pid":3}}}}"#),
      (.write(.empty), #"{"write":{"response":{"empty":{}}}}"#),
      (.setting(BridgeAXSettingResponse(enabled: false)), #"{"setting":{"response":{"enabled":false}}}"#),
      (
        .displays(BridgeAXDisplayInventory(displayScopedInteractions: true, displayScopedTrees: false, displayScopedQuiescence: false, displays: [.init(uniqueID: "main", displayID: 1)])),
        #"{"displays":{"inventory":{"displayScopedInteractions":true,"displayScopedQuiescence":false,"displayScopedTrees":false,"displays":[{"displayID":1,"uniqueID":"main"}]}}}"#
      ),
      (
        .settingSnapshot(BridgeAXSettingSnapshot(setting: "reduce-motion", enabled: true, otherSettings: ["zoom": .failure(BridgeAXFailure(message: "no", kind: .capabilityUnavailable))])),
        #"{"settingSnapshot":{"snapshot":{"enabled":true,"otherSettings":{"zoom":{"failure":{"reason":{"error":"no","error_kind":"capability_unavailable"}}}},"setting":"reduce-motion"}}}"#
      ),
      (.quiescence(.state(.busy, busySignals: [.animationsInactive], pid: 5)), #"{"quiescence":{"event":{"state":{"busySignals":["animations_inactive"],"pid":5,"state":"busy"}}}}"#),
      (.quiescence(.targetExited(pid: 6)), #"{"quiescence":{"event":{"targetExited":{"pid":6}}}}"#),
      (.failure(BridgeAXFailure(message: "no", kind: .badRequest)), #"{"failure":{"reason":{"error":"no","error_kind":"bad_request"}}}"#),
    ]
    for (answer, json) in cases {
      #expect(try text(answer) == json, "\(answer)")
      #expect(try JSONDecoder().decode(BridgeAXAnswer.self, from: Data(json.utf8)) == answer, "\(json)")
    }
  }

  // The guest will encode these types itself, so what they write must decode back to the same answer.
  @Test
  func everyAnswerRoundTripsThroughItsOwnEncoding() throws {
    var node = BridgeAXNode()
    node.label = .string("Wi-Fi")
    #expect(
      try roundTrip(
        BridgeAXOutcome<BridgeAXTreeResponse>.success(
          BridgeAXTreeResponse(
            tree: node, pid: 3, truncated: true, automation: BridgeAXAutomationState(enabled: true, asserted: false),
            phases: BridgeAXGuestPhases(traverseMilliseconds: 1.5, machRoundTrips: 2), method: .runningBoard,
            modal: BridgeAXModal(kind: .system, elementType: "SBAlertItemWindow", label: nil))))
        == .success(
          BridgeAXTreeResponse(
            tree: node, pid: 3, truncated: true, automation: BridgeAXAutomationState(enabled: true, asserted: false),
            phases: BridgeAXGuestPhases(traverseMilliseconds: 1.5, machRoundTrips: 2), method: .runningBoard,
            modal: BridgeAXModal(kind: .system, elementType: "SBAlertItemWindow", label: nil))))
    for hit in [BridgeAXHitTestResponse.element(node, pid: 7), .empty] {
      #expect(try roundTrip(BridgeAXOutcome.success(hit)) == .success(hit))
    }
    for write in [BridgeAXWriteResponse.written(pid: 7), .empty] {
      #expect(try roundTrip(BridgeAXOutcome.success(write)) == .success(write))
    }
    let snapshot = BridgeAXSettingSnapshot(
      setting: "voiceover", enabled: true,
      otherSettings: [
        "zoom": .success(BridgeAXSettingResponse(enabled: false)),
        "invert": .failure(BridgeAXFailure(message: "no", kind: .capabilityUnavailable)),
      ])
    #expect(try roundTrip(BridgeAXOutcome.success(snapshot)) == .success(snapshot))
    for event in [
      BridgeAXQuiescenceEvent.state(.busy, busySignals: [.runLoopIdle, .animationsInactive], pid: 5), .state(.quiet, busySignals: [], pid: 5),
      .touchesCompleted(pid: 5), .targetChanged(pid: 6), .targetExited(pid: 6),
    ] {
      #expect(try roundTrip(BridgeAXOutcome.success(event)) == .success(event))
    }
    let failure = BridgeAXFailure(
      message: "busy", kind: .applicationNotResponding, pid: 42, axError: -25204, timeoutSeconds: 1.5, outstanding: true, effect: .unknown)
    #expect(try roundTrip(BridgeAXOutcome<BridgeAXWriteResponse>.failure(failure)) == .failure(failure))
  }
}

/// Locates the test bundle, which carries the fixtures.
private final class BundleFinder {
  // Generated coders spell these keys themselves; they must be the vocabulary's spelling.
  @Test
  func generatedKeysSpellTheWireVocabulary() {
    #expect(Set(BridgeAXFailure.CodingKeys.allCases.map(\.stringValue)).isSubset(of: Set(["error", "error_kind", "pid", "ax_error", "timeout_seconds", "outstanding", "effect"])))
    for key in BridgeAXFailure.CodingKeys.allCases {
      #expect(BridgeAXWire.Envelope(rawValue: key.stringValue) != nil, "\(key)")
    }
    for key in BridgeAXGuestPhases.CodingKeys.allCases {
      #expect(BridgeAXWire.Phase(rawValue: key.stringValue) != nil, "\(key)")
    }
  }
}

/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorBridgeProtocol
import Foundation
import Testing

private final class BridgeAXOutcomeFixtureBundleToken {}

// The frames below are spelled as the guest writes them today, so the types decode what is on the wire rather than
// what they would have written themselves.
@Suite
struct BridgeAXOutcomeTests {
  /// A `describe` of the Settings root on an iPhone simulator: 164 elements, as the guest sent it.
  private static func settingsRead() throws -> Data {
    let url = try #require(
      Bundle(for: BridgeAXOutcomeFixtureBundleToken.self).url(forResource: "ax-describe-settings", withExtension: "json"))
    return try Data(contentsOf: url)
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

  // MARK: - Trees

  @Test
  func aSettingsReadDecodesIntoATypedTree() throws {
    let outcome = try JSONDecoder().decode(BridgeAXOutcome<BridgeAXTreeResponse>.self, from: Self.settingsRead())
    guard case let .success(read) = outcome else {
      Issue.record("expected a tree, got \(outcome)")
      return
    }
    #expect(read.pid == 69447)
    #expect(!read.truncated)
    #expect(read.method == .windowServer)
    #expect(read.automation == BridgeAXAutomationState(enabled: true, asserted: false))
    #expect(read.phases?.machRoundTrips == 1)
    #expect(read.modal == nil)
    #expect(count(read.tree) == 164)
    #expect(read.tree.label == .string("Settings"))
    #expect(read.tree.automationType != nil)
    #expect(read.tree.frame?.width != nil)
  }

  @Test
  func aSettingsReadReencodesAsTheFrameTheGuestSent() throws {
    let data = try Self.settingsRead()
    let outcome = try JSONDecoder().decode(BridgeAXOutcome<BridgeAXTreeResponse>.self, from: data)
    #expect(try jsonObject(JSONEncoder().encode(outcome)) == jsonObject(data))
  }

  @Test
  func aNodeCarriesEveryAttributeTheWireNames() throws {
    let node = try decode(
      BridgeAXNode.self,
      #"""
      {"XC_kAXXCAttributeElementType":"UIButton","XC_kAXXCAttributeElementBaseType":9,"XC_kAXXCAttributeLabel":"Done",
       "XC_kAXXCAttributeValue":0.5,"XC_kAXXCAttributeIdentifier":"done",
       "XC_kAXXCAttributeFrame":{"X":10,"Y":20.5,"Width":100,"Height":null},"XC_kAXXCAttributeAutomationType":9,
       "XC_kAXXCAttributeTraits":1,"XC_kAXXCAttributeChildren":[],"XC_kAXXCAttributeWindowDisplayId":3,
       "XC_kAXXCAttributeIsVisible":0,"XC_kAXXCAttributeVisiblePoint":{"X":-1,"Y":-1},"XC_kAXXCAttributeCenterPoint":{"X":60,"Y":45},
       "XC_kAXXCAttributeIsUserInteractionEnabled":1,"FBIsEnabled":true,"FBTranslatorRole":4,"FBTranslatorSubrole":12,
       "FBTraits":9007199254740993,"FBElementIdentity":105553116266496,"FBAttributeReadFailures":{"XC_kAXXCAttributeValue":"timed out"},
       "FBExplainedBy":{"XC_kAXXCAttributeElementType":"SBAlertItemWindow","XC_kAXXCAttributeLabel":null}}
      """#)
    #expect(node.elementType == .string("UIButton"))
    #expect(node.elementBaseType == .integer(9))
    #expect(node.label == .string("Done"))
    #expect(node.value == .number(0.5))
    #expect(node.identifier == .string("done"))
    #expect(node.frame == BridgeAXRect(x: 10, y: 20.5, width: 100, height: nil))
    #expect(node.automationType == 9)
    #expect(node.xcTraits == 1)
    #expect(node.children == [])
    #expect(node.windowDisplayID == 3)
    #expect(node.isVisible == false)
    #expect(node.visiblePoint == BridgeAXPoint(x: -1, y: -1))
    #expect(node.centerPoint == BridgeAXPoint(x: 60, y: 45))
    #expect(node.userInteractionEnabled == true)
    #expect(node.isEnabled == true)
    #expect(node.translatorRole == 4)
    #expect(node.translatorSubrole == 12)
    #expect(node.traits == 9_007_199_254_740_993)
    #expect(node.elementIdentity == 105_553_116_266_496)
    #expect(node.attributeReadFailures == ["XC_kAXXCAttributeValue": "timed out"])
    #expect(node.explainedBy?.elementType == .string("SBAlertItemWindow"))
    #expect(node.explainedBy?.label == nil)
    #expect(try roundTrip(node) == node)
  }

  @Test
  func aScalarKeepsTheKindItArrivedAs() throws {
    #expect(try decode([BridgeAXScalar].self, #"["9",9,9.5,true]"#) == [.string("9"), .integer(9), .number(9.5), .bool(true)])
    let scalars: [BridgeAXScalar] = [.string("9"), .integer(-9), .number(9.5), .bool(false)]
    #expect(try roundTrip(scalars) == scalars)
  }

  @Test
  func aNodeWithNothingReadCarriesNothing() throws {
    let node = try decode(BridgeAXNode.self, "{}")
    #expect(node == BridgeAXNode())
    #expect(try jsonObject(JSONEncoder().encode(node)) == [:])
  }

  @Test
  func aNonFiniteCoordinateTravelsAsNull() throws {
    let rect = BridgeAXRect(x: .infinity, y: 0, width: .nan, height: nil)
    #expect(try jsonObject(JSONEncoder().encode(rect)) == ["X": NSNull(), "Y": 0, "Width": NSNull(), "Height": NSNull()])
    #expect(try roundTrip(rect) == BridgeAXRect(x: nil, y: 0, width: nil, height: nil))
  }

  // MARK: - Failures

  @Test
  func everyFailureTheGuestWritesDecodes() throws {
    let cases: [(String, BridgeAXFailure)] = [
      (#"{"ok":false,"error":"no pid"}"#, BridgeAXFailure(message: "no pid")),
      (
        #"{"ok":false,"error":"gone","error_kind":"application_unavailable","pid":42}"#,
        BridgeAXFailure(message: "gone", kind: .applicationUnavailable, pid: 42)
      ),
      (
        #"{"ok":false,"error":"raised","error_kind":"runtime_failed","ax_error":-25204,"pid":42}"#,
        BridgeAXFailure(message: "raised", kind: .runtimeFailed, pid: 42, axError: -25204)
      ),
      (
        #"{"ok":false,"error":"busy","error_kind":"application_not_responding","pid":42,"timeout_seconds":1.5,"outstanding":true}"#,
        BridgeAXFailure(message: "busy", kind: .applicationNotResponding, pid: 42, timeoutSeconds: 1.5, outstanding: true)
      ),
      (
        #"{"ok":false,"error":"moved","error_kind":"assertion_failed","effect":"none"}"#,
        BridgeAXFailure(message: "moved", kind: .assertionFailed, effect: BridgeAXWire.Effect.none)
      ),
      (
        #"{"ok":false,"error":"no displays","error_kind":"capability_unavailable"}"#,
        BridgeAXFailure(message: "no displays", kind: .capabilityUnavailable)
      ),
    ]
    for (json, failure) in cases {
      let outcome = try decode(BridgeAXOutcome<BridgeAXTreeResponse>.self, json)
      #expect(outcome == .failure(failure))
      #expect(try roundTrip(outcome) == outcome)
    }
  }

  @Test
  func aKindThisRevisionDoesNotKnowDegradesToNone() throws {
    let outcome = try decode(BridgeAXOutcome<BridgeAXSettingResponse>.self, #"{"ok":false,"error":"new","error_kind":"from_the_future"}"#)
    #expect(outcome == .failure(BridgeAXFailure(message: "new")))
  }

  @Test
  func aFailureDecodesWhateverTheVerbWouldHaveAnswered() throws {
    let json = #"{"ok":false,"error":"no reader","error_kind":"reader_unavailable"}"#
    let failure = BridgeAXFailure(message: "no reader", kind: .readerUnavailable)
    #expect(try decode(BridgeAXOutcome<BridgeAXHitTestResponse>.self, json) == .failure(failure))
    #expect(try decode(BridgeAXOutcome<BridgeAXWriteResponse>.self, json) == .failure(failure))
    #expect(try decode(BridgeAXOutcome<BridgeAXDisplayInventory>.self, json) == .failure(failure))
    #expect(try decode(BridgeAXOutcome<BridgeAXQuiescenceEvent>.self, json) == .failure(failure))
  }

  // MARK: - Other verbs

  @Test
  func aHitTestAnswersWithTheElementOrWithNothing() throws {
    let element = try decode(
      BridgeAXOutcome<BridgeAXHitTestResponse>.self, #"{"ok":true,"tree":{"XC_kAXXCAttributeLabel":"Wi-Fi"},"pid":7}"#)
    var node = BridgeAXNode()
    node.label = .string("Wi-Fi")
    #expect(element == .success(.element(node, pid: 7)))
    #expect(try decode(BridgeAXOutcome<BridgeAXHitTestResponse>.self, #"{"ok":true,"empty":true}"#) == .success(.empty))
    #expect(try roundTrip(element) == element)
  }

  @Test
  func aWriteAnswersWithTheApplicationWrittenToOrWithNothing() throws {
    #expect(try decode(BridgeAXOutcome<BridgeAXWriteResponse>.self, #"{"ok":true,"pid":7}"#) == .success(.written(pid: 7)))
    #expect(try decode(BridgeAXOutcome<BridgeAXWriteResponse>.self, #"{"ok":true,"empty":true}"#) == .success(.empty))
    #expect(try roundTrip(BridgeAXOutcome<BridgeAXWriteResponse>.success(.written(pid: 7))) == .success(.written(pid: 7)))
  }

  @Test
  func aSettingAndTheDisplayInventoryAnswerBesideOk() throws {
    #expect(
      try decode(BridgeAXOutcome<BridgeAXSettingResponse>.self, #"{"ok":true,"enabled":false}"#)
        == .success(BridgeAXSettingResponse(enabled: false)))
    let inventory = try decode(
      BridgeAXOutcome<BridgeAXDisplayInventory>.self, #"{"ok":true,"displayScopedTrees":true,"displays":[{"uniqueID":"main","displayID":1}]}"#)
    #expect(
      inventory
        == .success(
          BridgeAXDisplayInventory(
            displayScopedInteractions: false, displayScopedTrees: true, displayScopedQuiescence: false,
            displays: [.init(uniqueID: "main", displayID: 1)])))
    #expect(try roundTrip(inventory) == inventory)
  }

  @Test
  func aTreeFromAFrontmostReadCarriesItsModal() throws {
    let outcome = try decode(
      BridgeAXOutcome<BridgeAXTreeResponse>.self,
      #"{"ok":true,"tree":{},"pid":3,"truncated":true,"method":"runningboard","modal":{"kind":"system","elementType":"SBAlertItemWindow"}}"#)
    #expect(
      outcome
        == .success(
          BridgeAXTreeResponse(
            tree: BridgeAXNode(), pid: 3, truncated: true, method: .runningBoard,
            modal: BridgeAXModal(kind: .system, elementType: "SBAlertItemWindow", label: nil))))
    #expect(try roundTrip(outcome) == outcome)
  }

  // MARK: - Streams

  @Test
  func aSettingsSnapshotCarriesTheOtherSettingsAsTheirOwnOutcomes() throws {
    let outcome = try decode(
      BridgeAXOutcome<BridgeAXSettingSnapshot>.self,
      #"""
      {"ok":true,"event":"snapshot","setting":"voiceover","enabled":true,
       "settings":{"zoom":{"ok":true,"enabled":false},"invert":{"ok":false,"error":"no","error_kind":"capability_unavailable"}}}
      """#)
    #expect(
      outcome
        == .success(
          BridgeAXSettingSnapshot(
            setting: "voiceover", enabled: true,
            otherSettings: [
              "zoom": .success(BridgeAXSettingResponse(enabled: false)),
              "invert": .failure(BridgeAXFailure(message: "no", kind: .capabilityUnavailable)),
            ])))
    #expect(try roundTrip(outcome) == outcome)
    let alone = BridgeAXOutcome<BridgeAXSettingSnapshot>.success(BridgeAXSettingSnapshot(setting: "zoom", enabled: false))
    #expect(try jsonObject(JSONEncoder().encode(alone)) == ["ok": true, "event": "snapshot", "setting": "zoom", "enabled": false])
  }

  @Test
  func everyQuiescenceEventDecodes() throws {
    let cases: [(String, BridgeAXQuiescenceEvent)] = [
      (
        #"{"ok":true,"event":"state","state":"busy","signals":["animations_inactive","run_loop_idle"],"pid":5}"#,
        .state(.busy, busySignals: [.animationsInactive, .runLoopIdle], pid: 5)
      ),
      (#"{"ok":true,"event":"state","state":"quiet","pid":5}"#, .state(.quiet, busySignals: [], pid: 5)),
      (#"{"ok":true,"event":"touches_completed","pid":5}"#, .touchesCompleted(pid: 5)),
      (#"{"ok":true,"event":"target_changed","pid":6}"#, .targetChanged(pid: 6)),
      (#"{"ok":true,"event":"target_exited","pid":6}"#, .targetExited(pid: 6)),
    ]
    for (json, event) in cases {
      let outcome = try decode(BridgeAXOutcome<BridgeAXQuiescenceEvent>.self, json)
      #expect(outcome == .success(event))
      #expect(try jsonObject(JSONEncoder().encode(outcome)) == jsonObject(Data(json.utf8)))
    }
  }
}

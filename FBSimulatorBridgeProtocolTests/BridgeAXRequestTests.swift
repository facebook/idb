/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorBridgeProtocol
import Foundation
import XCTest

final class BridgeAXRequestTests: XCTestCase {
  private let options = BridgeAXReadOptions(
    maxDepth: 7, maxNodes: 300, attributes: ["XC_kAXXCAttributeLabel"], explainUnreachable: true, traversal: .viewHierarchy, automationMode: false)

  func testEveryRequestDecodesFromTheFrameItIsSentIn() throws {
    let requests: [BridgeAXRequest] = [
      .read(pid: 42, options: options, displayID: 3),
      .read(pid: 42, options: BridgeAXReadOptions(maxDepth: 1, maxNodes: 2, attributes: nil, explainUnreachable: false, traversal: .semantic, automationMode: nil)),
      .read(pid: 42, options: BridgeAXReadOptions(maxDepth: 1, maxNodes: 2, attributes: nil, explainUnreachable: false, traversal: .singleFetch, automationMode: true)),
      .readFrontmost(x: 10.5, y: 20, method: .centerPoint, options: options),
      .readFrontmost(x: 0, y: 0, method: .runningBoard, options: options, displayID: 9),
      .hitTest(x: 1, y: 2, attributes: nil),
      .hitTest(x: 1, y: 2, attributes: ["XC_kAXXCAttributeFrame"], displayID: 4, pid: 77),
      .write(BridgeAXWriteRequest(kind: .perform(.scrollDown), x: 3, y: 4, pid: nil, assertion: nil)),
      .write(
        BridgeAXWriteRequest(
          kind: .setValue("hello"), x: 3, y: 4, pid: 12, assertion: BridgeAXWriteAssertion(key: .visiblePoint, value: "{1, 2}"), displayID: 5,
          attributes: ["XC_kAXXCAttributeVisiblePoint"])),
      .deviceSettingRead("voiceover"),
      .deviceSettingWrite("reduce-motion", enabled: true),
      .quiescence(pid: nil, busyThresholdMs: nil, quietWindowMs: nil),
      .quiescence(pid: 8, busyThresholdMs: 5, quietWindowMs: 0, displayID: 2, method: .centerPoint, x: 6, y: 7),
      .displays,
    ]
    for request in requests {
      let frame = try BridgeRequest(command: request.command).encoded()
      XCTAssertEqual(try BridgeRequest.decode(frame).command, .accessibility(request))
      let parameters = try XCTUnwrap(BridgeRequest.accessibilityParameters(of: frame))
      XCTAssertEqual(try BridgeAXRequest(payload: parameters), request)
    }
  }

  func testOmittedReadFieldsTakeTheDefaults() throws {
    let request = try BridgeAXRequest(payload: ["verb": .string("describe"), "pid": .integer(5)])
    let defaults = BridgeAXReadOptions(
      maxDepth: BridgeAXReadOptions.defaultMaxDepth, maxNodes: BridgeAXReadOptions.defaultMaxNodes, attributes: nil, explainUnreachable: false,
      traversal: .viewHierarchy, automationMode: nil)
    XCTAssertEqual(request, .read(pid: 5, options: defaults))
  }

  func testASingleFetchOutranksTheTranslatorAndStringFlagsReadAsFoundationDoes() throws {
    let request = try BridgeAXRequest(payload: [
      "verb": .string("describe"), "pid": .integer(5), "snapshotTree": .string("YES"), "translatorVocabulary": .bool(true), "explainUnreachable": .null,
    ])
    guard case let .read(_, options, _) = request else { return XCTFail("\(request)") }
    XCTAssertEqual(options.traversal, .singleFetch)
    XCTAssertFalse(options.explainUnreachable)
  }

  func testNonStringAttributesAreDropped() throws {
    let request = try BridgeAXRequest(payload: [
      "verb": .string("hittest"), "x": .integer(1), "y": .integer(2), "attributes": .array([.string("a"), .integer(3), .string("b")]),
    ])
    XCTAssertEqual(request, .hitTest(x: 1, y: 2, attributes: ["a", "b"]))
  }

  func testMalformedPayloadsNameWhatIsWrong() {
    let point: [String: BridgeJSONValue] = ["x": .integer(1), "y": .integer(2)]
    let cases: [([String: BridgeJSONValue], BridgeAXRequestError)] = [
      ([:], .unsupportedVerb(nil)),
      (["verb": .integer(3)], .unsupportedVerb(.integer(3))),
      (["verb": .string("dance")], .unsupportedVerb(.string("dance"))),
      (["verb": .string("describe"), "pid": .integer(0)], .nonPositivePid(0)),
      (["verb": .string("settings-get"), "pid": .integer(-4)], .nonPositivePid(-4)),
      (point.merging(["verb": .string("hittest"), "displayID": .integer(0)]) { $1 }, .invalidDisplayID),
      (point.merging(["verb": .string("hittest"), "displayID": .bool(true)]) { $1 }, .invalidDisplayID),
      (point.merging(["verb": .string("hittest"), "displayID": .number(1.5)]) { $1 }, .invalidDisplayID),
      (point.merging(["verb": .string("hittest"), "displayID": .null]) { $1 }, .invalidDisplayID),
      (["verb": .string("hittest"), "x": .string("left"), "y": .integer(2)], .missingPoint(.hitTest)),
      (["verb": .string("describe")], .missingPoint(.describe)),
      (point.merging(["verb": .string("describe"), "method": .string("guess")]) { $1 }, .unsupportedFrontmostMethod("guess")),
      (point.merging(["verb": .string("perform")]) { $1 }, .unsupportedAction(nil)),
      (point.merging(["verb": .string("perform"), "action": .string("tap")]) { $1 }, .unsupportedAction(.string("tap"))),
      (["verb": .string("perform"), "action": .string("press")], .missingPoint(.perform)),
      (point.merging(["verb": .string("setvalue"), "value": .integer(1)]) { $1 }, .missingValue),
      (point.merging(["verb": .string("setvalue"), "value": .string("v"), "assertKey": .string("XC_kAXXCAttributeLabel")]) { $1 }, .unpairedAssertion),
      (point.merging(["verb": .string("perform"), "action": .string("press"), "assertKey": .string("Nope"), "assertValue": .string("v")]) { $1 }, .unassertableKey("Nope")),
      (["verb": .string("settings-get")], .missingSetting),
      (["verb": .string("settings-set"), "setting": .string("voiceover"), "enabled": .string("yes")], .missingEnabled),
      (["verb": .string("quiet"), "busyThresholdMs": .integer(-1)], .negativeTunable(.busyThresholdMs, -1)),
      (["verb": .string("describe"), "pid": .integer(5), "snapshotTree": .null], .malformedFlag(.snapshotTree)),
      (["verb": .string("describe"), "pid": .integer(5), "translatorVocabulary": .array([])], .malformedFlag(.translatorVocabulary)),
      (["verb": .string("describe"), "pid": .integer(5), "explainUnreachable": .object([:])], .malformedFlag(.explainUnreachable)),
    ]
    for (payload, expected) in cases {
      XCTAssertThrowsError(try BridgeAXRequest(payload: payload), "\(payload)") { error in
        XCTAssertEqual(error as? BridgeAXRequestError, expected, "\(payload)")
      }
    }
  }

  func testAnUndecodableRequestFailsTheFrameButKeepsItsParameters() throws {
    let frame = Data(#"{"command":{"accessibility":{"_0":{"verb":"quiet","quietWindowMs":-1}}},"id":"bad","version":1}"#.utf8)
    XCTAssertThrowsError(try BridgeRequest.decode(frame))
    XCTAssertEqual(BridgeRequest.identity(of: frame), "bad")
    XCTAssertEqual(BridgeRequest.accessibilityParameters(of: frame), ["verb": .string("quiet"), "quietWindowMs": .integer(-1)])
    XCTAssertNil(BridgeRequest.accessibilityParameters(of: try BridgeRequest(command: .ping).encoded()))
  }

  func testClientTypesCarryTheTranslatorsIntegers() {
    let expected: [BridgeAXClientType: UInt64] = [
      .noClient: 0, .unidentified: 1, .application: 2, .xcodeHelper: 3, .xctest: 4, .scripter: 5, .systemEvents: 6, .voiceOver: 7,
      .switchControl: 8, .fullKeyboardAccess: 9, .voiceControl: 10, .accessibilityInspector: 11,
    ]
    XCTAssertEqual(Set(BridgeAXClientType.allCases), Set(expected.keys))
    for (clientType, value) in expected {
      XCTAssertEqual(clientType.rawValue, value, "\(clientType)")
    }
    XCTAssertNil(BridgeAXClientType(rawValue: 12))
  }

  func testClientTypesMapOntoTheRequestingClientTheGuestTranslatorInstalls() {
    let expected: [BridgeAXClientType: UInt32] = [
      .noClient: 0, .unidentified: 0, .application: 1, .xcodeHelper: 2, .xctest: 2, .scripter: 1, .systemEvents: 1, .voiceOver: 3,
      .switchControl: 4, .fullKeyboardAccess: 10, .voiceControl: 5, .accessibilityInspector: 12,
    ]
    for clientType in BridgeAXClientType.allCases {
      XCTAssertEqual(clientType.requestingClient.rawValue, expected[clientType], "\(clientType)")
    }
  }

  func testOnlyScriptingAndTestingClientsDeserveTheAutomationTree() {
    XCTAssertEqual(
      Set(BridgeAXClientType.allCases.filter(\.deservesAutomation)),
      [.application, .xcodeHelper, .xctest, .scripter, .systemEvents])
    XCTAssertEqual(Set(BridgeAXRequestingClient.allCases.filter(\.deservesAutomation)), [.scripting, .xctest, .typist])
  }

  func testRequestingClientsCarryTheRuntimesIntegers() {
    XCTAssertEqual(
      BridgeAXRequestingClient.allCases.map(\.rawValue),
      [0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15, 16, 17])
  }
}

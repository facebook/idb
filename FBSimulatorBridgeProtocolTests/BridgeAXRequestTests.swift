/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorBridgeProtocol
import Foundation
import Testing

@Suite
struct BridgeAXRequestTests {
  private let options = BridgeAXReadOptions(
    maxDepth: 7, maxNodes: 300, attributes: ["XC_kAXXCAttributeLabel"], explainUnreachable: true, traversal: .viewHierarchy, automationMode: false, clientType: .noClient)

  @Test
  func everyRequestDecodesFromTheFrameItIsSentIn() throws {
    let requests: [BridgeAXRequest] = [
      .read(pid: 42, options: options, displayID: 3),
      .read(pid: 42, options: BridgeAXReadOptions(maxDepth: 1, maxNodes: 2, attributes: nil, explainUnreachable: false, traversal: .semantic, automationMode: nil, clientType: .noClient)),
      .read(pid: 42, options: BridgeAXReadOptions(maxDepth: 1, maxNodes: 2, attributes: nil, explainUnreachable: false, traversal: .singleFetch, automationMode: true, clientType: .noClient)),
      .readFrontmost(x: 10.5, y: 20, method: .centerPoint, options: options),
      .readFrontmost(x: 0, y: 0, method: .runningBoard, options: options, displayID: 9),
      .hitTest(x: 1, y: 2, attributes: nil, clientType: .noClient),
      .hitTest(x: 1, y: 2, attributes: ["XC_kAXXCAttributeFrame"], clientType: .noClient, displayID: 4, pid: 77),
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
      #expect(try BridgeRequest.decode(frame).command == .accessibility(request))
      let parameters = try #require(BridgeRequest.accessibilityParameters(of: frame))
      #expect(try BridgeAXRequest(payload: parameters) == request)
    }
  }

  @Test
  func omittedReadFieldsTakeTheDefaults() throws {
    let request = try BridgeAXRequest(payload: ["verb": .string("describe"), "pid": .integer(5)])
    let defaults = BridgeAXReadOptions(
      maxDepth: BridgeAXReadOptions.defaultMaxDepth, maxNodes: BridgeAXReadOptions.defaultMaxNodes, attributes: nil, explainUnreachable: false,
      traversal: .viewHierarchy, automationMode: nil, clientType: .noClient)
    #expect(request == .read(pid: 5, options: defaults))
  }

  @Test
  func eachTraversalDecodesFromItsNameAndStringFlagsReadAsFoundationDoes() throws {
    for traversal in BridgeAXTraversal.allCases {
      let request = try BridgeAXRequest(payload: [
        "verb": .string("describe"), "pid": .integer(5), "traversal": .string(traversal.rawValue), "explainUnreachable": .string("NO"),
      ])
      guard case let .read(_, options, _) = request else {
        Issue.record("\(request)")
        return
      }
      #expect(options.traversal == traversal)
      #expect(!options.explainUnreachable)
    }
  }

  @Test
  func eachClientTypeDecodesFromItsIntegerOnReadsAndHitTests() throws {
    for clientType in BridgeAXClientType.allCases {
      let raw = BridgeJSONValue.integer(Int64(clientType.rawValue))
      guard case let .read(_, options, _) = try BridgeAXRequest(payload: ["verb": .string("describe"), "pid": .integer(5), "traversal": .string("semantic"), "clientType": raw]) else {
        Issue.record("not a read")
        return
      }
      #expect(options.clientType == clientType)
      guard case let .hitTest(_, _, _, hitClient, _, _) = try BridgeAXRequest(payload: ["verb": .string("hittest"), "x": .integer(1), "y": .integer(2), "clientType": raw])
      else {
        Issue.record("not a hit-test")
        return
      }
      #expect(hitClient == clientType)
    }
  }

  @Test
  func anXCTestTraversalAcceptsOnlyNoClient() throws {
    for traversal in [BridgeAXTraversal.viewHierarchy, .singleFetch] {
      guard
        case let .read(_, options, _) = try BridgeAXRequest(payload: [
          "verb": .string("describe"), "pid": .integer(5), "traversal": .string(traversal.rawValue), "clientType": .integer(0),
        ])
      else {
        Issue.record("not a read")
        return
      }
      #expect(options.clientType == .noClient)
    }
  }

  @Test
  func aRequestWithoutAClientTypeClaimsNoClient() throws {
    guard case let .read(_, options, _) = try BridgeAXRequest(payload: ["verb": .string("describe"), "pid": .integer(5)]) else {
      Issue.record("not a read")
      return
    }
    #expect(options.clientType == .noClient)
  }

  @Test
  func aReadWithoutATraversalWalksTheViewHierarchy() throws {
    guard case let .read(_, options, _) = try BridgeAXRequest(payload: ["verb": .string("describe"), "pid": .integer(5)]) else {
      Issue.record("not a read")
      return
    }
    #expect(options.traversal == .viewHierarchy)
  }

  @Test
  func nonStringAttributesAreDropped() throws {
    let request = try BridgeAXRequest(payload: [
      "verb": .string("hittest"), "x": .integer(1), "y": .integer(2), "attributes": .array([.string("a"), .integer(3), .string("b")]),
    ])
    #expect(request == .hitTest(x: 1, y: 2, attributes: ["a", "b"], clientType: .noClient))
  }

  @Test
  func malformedPayloadsNameWhatIsWrong() {
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
      (["verb": .string("describe"), "pid": .integer(5), "traversal": .null], .unsupportedTraversal(.null)),
      (["verb": .string("describe"), "pid": .integer(5), "traversal": .string("sideways")], .unsupportedTraversal(.string("sideways"))),
      (["verb": .string("describe"), "pid": .integer(5), "clientType": .integer(12)], .unsupportedClientType(.integer(12))),
      (["verb": .string("describe"), "pid": .integer(5), "clientType": .integer(4)], .clientTypeNeedsSemanticTraversal(.viewHierarchy)),
      (["verb": .string("describe"), "pid": .integer(5), "traversal": .string("single-fetch"), "clientType": .integer(4)], .clientTypeNeedsSemanticTraversal(.singleFetch)),
      (["verb": .string("describe"), "pid": .integer(5), "clientType": .string("xctest")], .unsupportedClientType(.string("xctest"))),
      (["verb": .string("hittest"), "x": .integer(1), "y": .integer(2), "clientType": .integer(-1)], .unsupportedClientType(.integer(-1))),
      (["verb": .string("describe"), "pid": .integer(5), "explainUnreachable": .object([:])], .malformedFlag(.explainUnreachable)),
    ]
    for (payload, expected) in cases {
      #expect(throws: expected, "\(payload)") { try BridgeAXRequest(payload: payload) }
    }
  }

  @Test
  func anUndecodableRequestFailsTheFrameButKeepsItsParameters() throws {
    let frame = Data(#"{"command":{"accessibility":{"_0":{"verb":"quiet","quietWindowMs":-1}}},"id":"bad","version":2}"#.utf8)
    #expect(throws: (any Error).self) { try BridgeRequest.decode(frame) }
    #expect(BridgeRequest.identity(of: frame) == "bad")
    #expect(BridgeRequest.accessibilityParameters(of: frame) == ["verb": .string("quiet"), "quietWindowMs": .integer(-1)])
    #expect(BridgeRequest.accessibilityParameters(of: try BridgeRequest(command: .ping).encoded()) == nil)
  }

  // The exact payloads the host sends for its default requests. A change to any of these is a change to
  // what every guest receives, so it must be deliberate.
  @Test
  func theDefaultReadPayloadsAreUnchanged() {
    let base: [String: Any] = ["verb": "describe", "pid": 42, "maxDepth": 100, "maxNodes": 5000, "automationMode": true, "clientType": 0]
    let traversalKeys: [BridgeAXTraversal: [String: Any]] = [
      .viewHierarchy: ["traversal": "view-hierarchy"],
      .semantic: ["traversal": "semantic"],
      .singleFetch: ["traversal": "single-fetch"],
    ]
    for traversal in BridgeAXTraversal.allCases {
      let options = BridgeAXReadOptions(
        maxDepth: BridgeAXReadOptions.defaultMaxDepth, maxNodes: BridgeAXReadOptions.defaultMaxNodes, attributes: nil,
        explainUnreachable: false, traversal: traversal, automationMode: true, clientType: .noClient)
      let expected = base.merging(traversalKeys[traversal]!) { $1 }
      #expect(NSDictionary(dictionary: BridgeAXRequest.read(pid: 42, options: options).payload) == NSDictionary(dictionary: expected), "\(traversal)")
    }
  }

  @Test
  func theDefaultFrontmostReadPayloadIsUnchanged() {
    let options = BridgeAXReadOptions(
      maxDepth: BridgeAXReadOptions.defaultMaxDepth, maxNodes: BridgeAXReadOptions.defaultMaxNodes, attributes: nil,
      explainUnreachable: false, traversal: .singleFetch, automationMode: true, clientType: .noClient)
    #expect(
      NSDictionary(dictionary: BridgeAXRequest.readFrontmost(x: 195, y: 422, method: .windowServer, options: options).payload)
        == NSDictionary(dictionary: [
          "verb": "describe", "x": 195.0, "y": 422.0, "method": "window-server", "maxDepth": 100, "maxNodes": 5000, "traversal": "single-fetch", "clientType": 0,
          "automationMode": true,
        ]))
  }

  @Test
  func theDefaultHitTestPayloadIsUnchanged() {
    #expect(
      NSDictionary(dictionary: BridgeAXRequest.hitTest(x: 1, y: 2, attributes: nil, clientType: .noClient).payload) == NSDictionary(dictionary: ["verb": "hittest", "x": 1.0, "y": 2.0, "clientType": 0]))
  }

  @Test
  func aReadThatLeavesAutomationModeAloneOmitsIt() {
    let options = BridgeAXReadOptions(maxDepth: 1, maxNodes: 1, attributes: nil, explainUnreachable: false, traversal: .viewHierarchy, automationMode: nil, clientType: .noClient)
    #expect(BridgeAXRequest.read(pid: 1, options: options).payload["automationMode"] == nil)
  }

  @Test
  func clientTypesCarryTheTranslatorsIntegers() {
    let expected: [BridgeAXClientType: UInt64] = [
      .noClient: 0, .unidentified: 1, .application: 2, .xcodeHelper: 3, .xctest: 4, .scripter: 5, .systemEvents: 6, .voiceOver: 7,
      .switchControl: 8, .fullKeyboardAccess: 9, .voiceControl: 10, .accessibilityInspector: 11,
    ]
    #expect(Set(BridgeAXClientType.allCases) == Set(expected.keys))
    for (clientType, value) in expected {
      #expect(clientType.rawValue == value, "\(clientType)")
    }
    #expect(BridgeAXClientType(rawValue: 12) == nil)
  }

  // Names are an output and command-line contract: pinned literally so a renamed case shows up here.
  @Test
  func clientTypesCarryStableNames() {
    #expect(
      BridgeAXClientType.allCases.map(\.name) == [
        "noClient", "unidentified", "application", "xcodeHelper", "xctest", "scripter", "systemEvents", "voiceOver", "switchControl",
        "fullKeyboardAccess", "voiceControl", "accessibilityInspector",
      ])
    for clientType in BridgeAXClientType.allCases {
      #expect(BridgeAXClientType(name: clientType.name) == clientType)
    }
    #expect(BridgeAXClientType(name: "XCTest") == nil)
  }

  @Test
  func clientTypesMapOntoTheRequestingClientTheGuestTranslatorInstalls() {
    let expected: [BridgeAXClientType: UInt32] = [
      .noClient: 0, .unidentified: 0, .application: 1, .xcodeHelper: 2, .xctest: 2, .scripter: 1, .systemEvents: 1, .voiceOver: 3,
      .switchControl: 4, .fullKeyboardAccess: 10, .voiceControl: 5, .accessibilityInspector: 12,
    ]
    for clientType in BridgeAXClientType.allCases {
      #expect(clientType.requestingClient.rawValue == expected[clientType], "\(clientType)")
    }
  }

  @Test
  func onlyScriptingAndTestingClientsDeserveTheAutomationTree() {
    #expect(
      Set(BridgeAXClientType.allCases.filter(\.deservesAutomation)) == [.application, .xcodeHelper, .xctest, .scripter, .systemEvents])
    #expect(Set(BridgeAXRequestingClient.allCases.filter(\.deservesAutomation)) == [.scripting, .xctest, .typist])
  }

  @Test
  func requestingClientsCarryTheRuntimesIntegers() {
    #expect(
      BridgeAXRequestingClient.allCases.map(\.rawValue) == [0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15, 16, 17])
  }
}

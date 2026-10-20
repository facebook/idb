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

  /// Every request the host sends, beside the JSON it travels as: the case's name, then its fields. Changing a line
  /// here changes what every guest receives, so it must be deliberate.
  private var sentRequests: [(BridgeAXRequest, String)] {
    [
      (.read(pid: 42, options: options, displayID: 3), #"{"read":{"displayID":3,"options":{"attributes":["XC_kAXXCAttributeLabel"],"automationMode":false,"clientType":0,"explainUnreachable":true,"maxDepth":7,"maxNodes":300,"traversal":"view-hierarchy"},"pid":42}}"#),
      (
        .read(pid: 42, options: BridgeAXReadOptions(maxDepth: 1, maxNodes: 2, attributes: nil, explainUnreachable: false, traversal: .semantic, automationMode: nil, clientType: .xctest)),
        #"{"read":{"options":{"clientType":4,"explainUnreachable":false,"maxDepth":1,"maxNodes":2,"traversal":"semantic"},"pid":42}}"#
      ),
      (
        .read(pid: 42, options: BridgeAXReadOptions(maxDepth: 1, maxNodes: 2, attributes: nil, explainUnreachable: false, traversal: .singleFetch, automationMode: true, clientType: .noClient)),
        #"{"read":{"options":{"automationMode":true,"clientType":0,"explainUnreachable":false,"maxDepth":1,"maxNodes":2,"traversal":"single-fetch"},"pid":42}}"#
      ),
      (.readFrontmost(x: 10.5, y: 20, method: .centerPoint, options: options), #"{"readFrontmost":{"method":"center-point","options":{"attributes":["XC_kAXXCAttributeLabel"],"automationMode":false,"clientType":0,"explainUnreachable":true,"maxDepth":7,"maxNodes":300,"traversal":"view-hierarchy"},"x":10.5,"y":20}}"#),
      (.readFrontmost(x: 0, y: 0, method: .runningBoard, options: options, displayID: 9), #"{"readFrontmost":{"displayID":9,"method":"runningboard","options":{"attributes":["XC_kAXXCAttributeLabel"],"automationMode":false,"clientType":0,"explainUnreachable":true,"maxDepth":7,"maxNodes":300,"traversal":"view-hierarchy"},"x":0,"y":0}}"#),
      (.hitTest(x: 1, y: 2, attributes: nil, clientType: .noClient), #"{"hitTest":{"clientType":0,"x":1,"y":2}}"#),
      (
        .hitTest(x: 1, y: 2, attributes: ["XC_kAXXCAttributeFrame"], clientType: .voiceOver, displayID: 4, pid: 77),
        #"{"hitTest":{"attributes":["XC_kAXXCAttributeFrame"],"clientType":7,"displayID":4,"pid":77,"x":1,"y":2}}"#
      ),
      (
        .write(BridgeAXWriteRequest(kind: .perform(.scrollDown), x: 3, y: 4, pid: nil, assertion: nil)),
        #"{"write":{"request":{"kind":{"perform":{"action":"scroll-down"}},"x":3,"y":4}}}"#
      ),
      (
        .write(
          BridgeAXWriteRequest(
            kind: .setValue("hello"), x: 3, y: 4, pid: 12, assertion: BridgeAXWriteAssertion(key: .visiblePoint, value: "{1, 2}"), displayID: 5,
            attributes: ["XC_kAXXCAttributeVisiblePoint"])),
        #"{"write":{"request":{"assertion":{"key":"XC_kAXXCAttributeVisiblePoint","value":"{1, 2}"},"attributes":["XC_kAXXCAttributeVisiblePoint"],"displayID":5,"kind":{"setValue":{"value":"hello"}},"pid":12,"x":3,"y":4}}}"#
      ),
      (.deviceSettingRead("voiceover"), #"{"deviceSettingRead":{"setting":"voiceover"}}"#),
      (.deviceSettingWrite("reduce-motion", enabled: true), #"{"deviceSettingWrite":{"enabled":true,"setting":"reduce-motion"}}"#),
      (.deviceSettingChanges("reduce-motion"), #"{"deviceSettingChanges":{"setting":"reduce-motion"}}"#),
      (.quiescence(pid: nil, busyThresholdMs: nil, quietWindowMs: nil), #"{"quiescence":{"method":"window-server","x":0,"y":0}}"#),
      (
        .quiescence(pid: 8, busyThresholdMs: 5, quietWindowMs: 0, displayID: 2, method: .centerPoint, x: 6, y: 7),
        #"{"quiescence":{"busyThresholdMs":5,"displayID":2,"method":"center-point","pid":8,"quietWindowMs":0,"x":6,"y":7}}"#
      ),
      (.displays, #"{"displays":{}}"#),
    ]
  }

  @Test
  func everyRequestIsSentAsItsCase() throws {
    for (request, json) in sentRequests {
      let frame = try BridgeRequest(command: request.command, id: "pinned").encoded()
      #expect(
        String(decoding: frame, as: UTF8.self)
          == #"{"command":{"accessibility":{"action":"# + json + #"}},"id":"pinned","version":\#(BridgeRequest.currentVersion)}"#)
    }
  }

  @Test
  func everyRequestDecodesFromTheFrameItIsSentIn() throws {
    for (request, _) in sentRequests {
      let frame = try BridgeRequest(command: request.command).encoded()
      #expect(try BridgeRequest.decode(frame).command == .accessibility(request))
    }
  }

  @Test
  func settingsObserveDoesNotReplayAfterAConnectionFailure() {
    #expect(!BridgeAXRequest.deviceSettingChanges("reduce-motion").mayRetry)
  }

  // What a request means, rather than how it is spelled: checked for every request, however it arrived.
  @Test
  func aRequestThatMeansNothingIsInvalid() {
    let point = BridgeAXWriteRequest(kind: .perform(.press), x: 1, y: 2, pid: 0, assertion: nil)
    let semantic = BridgeAXReadOptions(maxDepth: 1, maxNodes: 1, attributes: nil, explainUnreachable: false, traversal: .viewHierarchy, automationMode: nil, clientType: .xctest)
    let cases: [(BridgeAXRequest, BridgeAXRequestError)] = [
      (.read(pid: 0, options: options), .nonPositivePid(0)),
      (.hitTest(x: 1, y: 2, attributes: nil, clientType: .noClient, pid: -4), .nonPositivePid(-4)),
      (.write(point), .nonPositivePid(0)),
      (.quiescence(pid: -1, busyThresholdMs: nil, quietWindowMs: nil), .nonPositivePid(-1)),
      (.read(pid: 5, options: options, displayID: 0), .invalidDisplayID),
      (.readFrontmost(x: 1, y: 2, method: .windowServer, options: options, displayID: 0), .invalidDisplayID),
      (.read(pid: 5, options: semantic), .clientTypeNeedsSemanticTraversal(.viewHierarchy)),
      (.quiescence(pid: nil, busyThresholdMs: -1, quietWindowMs: nil), .negativeTunable(.busyThresholdMs, -1)),
      (.quiescence(pid: nil, busyThresholdMs: nil, quietWindowMs: -2), .negativeTunable(.quietWindowMs, -2)),
    ]
    for (request, expected) in cases {
      #expect(throws: expected, "\(request)") { try request.validate() }
    }
    for (request, _) in sentRequests {
      #expect(throws: Never.self, "\(request)") { try request.validate() }
    }
  }

  // The guest answers a request it cannot use with what is wrong with it, rather than failing the frame.
  @Test
  func anUnusableRequestFailsTheFrameButSaysWhy() throws {
    func frame(_ action: String) -> Data {
      Data(#"{"command":{"accessibility":{"action":\#(action)}},"id":"bad","version":\#(BridgeRequest.currentVersion)}"#.utf8)
    }
    let invalid = frame(#"{"quiescence":{"method":"window-server","quietWindowMs":-1,"x":0,"y":0}}"#)
    #expect(BridgeRequest.identity(of: invalid) == "bad")
    #expect(BridgeRequest.accessibilityRequestError(of: invalid) == .negativeTunable(.quietWindowMs, -1))
    let undecodable = frame(#"{"dance":{}}"#)
    #expect(throws: (any Error).self) { try BridgeRequest.decode(undecodable) }
    guard case .undecodable? = BridgeRequest.accessibilityRequestError(of: undecodable) else {
      Issue.record("an action that is no request should be undecodable")
      return
    }
    #expect(BridgeRequest.accessibilityRequestError(of: try BridgeRequest(command: .ping).encoded()) == nil)
    #expect(BridgeRequest.accessibilityRequestError(of: try BridgeRequest(command: .accessibility(.displays)).encoded()) == nil)
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

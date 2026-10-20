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
struct BridgeProtocolTests {
  private static func readOptions(maxDepth: Int = 1, maxNodes: Int = 2, automationMode: Bool? = nil) -> BridgeAXReadOptions {
    BridgeAXReadOptions(maxDepth: maxDepth, maxNodes: maxNodes, attributes: nil, explainUnreachable: false, traversal: .viewHierarchy, automationMode: automationMode, clientType: .noClient)
  }

  @Test
  func everyServiceUsesTheSameRequestForArgumentsAndFrames() throws {
    let commands: [BridgeCommand] = [
      .clearContacts, .clearPhotos,
      .dynamicStore(.snapshot(key: "dns")), .dynamicStore(.restore(key: "State:/custom", snapshot: Data([0, 255]))),
      .dns(.list), .dns(.set(servers: ["1.1.1.1", "::1"])), .dns(.clear),
      .proxy(.list), .proxy(.set(host: "localhost", port: 8080, kind: .http)),
      .proxy(.set(host: "::1", port: 1080, kind: .socks)), .proxy(.clear),
      .notifications(.list(bundleID: nil)), .notifications(.list(bundleID: "com.example.app")),
      .notifications(.approve(bundleID: "com.example.app")), .notifications(.revoke(bundleID: "com.example.app")),
      .notifications(.delivered(bundleID: "com.example.app")), .notifications(.clearDelivered(bundleID: "com.example.app")),
      .health(.list(bundleID: "com.example.app")), .health(.clear(bundleID: "com.example.app")),
      .health(.approve(bundleID: "com.example.app", typeIDs: ["step"])),
      .health(.revoke(bundleID: "com.example.app", typeIDs: [])),
      .accessibility(.read(pid: 42, options: Self.readOptions(automationMode: false))),
      .ping, .shutdown,
    ]
    for command in commands {
      let request = BridgeRequest(command: command, id: "request-1")
      let arguments = try request.arguments
      #expect(arguments.count == 2)
      #expect(arguments[0] == "rpc")
      let data = Data(arguments[1].utf8)
      #expect(try BridgeRequest.decode(data) == request)
      #expect(try request.encoded() == data)
    }
  }

  @Test
  func mutationsCannotBeRetried() {
    let commands: [BridgeCommand] = [
      .clearContacts, .clearPhotos, .dns(.clear), .dns(.set(servers: [])), .proxy(.clear),
      .proxy(.set(host: "localhost", port: 8080, kind: .http)),
      .notifications(.approve(bundleID: "app")), .notifications(.revoke(bundleID: "app")),
      .notifications(.clearDelivered(bundleID: "app")),
      .health(.approve(bundleID: "app", typeIDs: [])), .health(.revoke(bundleID: "app", typeIDs: [])),
      .health(.clear(bundleID: "app")), .shutdown, .dynamicStore(.restore(key: "dns", snapshot: Data())),
      .accessibility(.write(BridgeAXWriteRequest(kind: .perform(.press), x: 1, y: 2, pid: nil, assertion: nil))),
      .accessibility(.write(BridgeAXWriteRequest(kind: .setValue("v"), x: 1, y: 2, pid: nil, assertion: nil))),
      .accessibility(.deviceSettingWrite("voiceover", enabled: true)),
      .accessibility(.quiescence(pid: nil, busyThresholdMs: nil, quietWindowMs: nil)),
    ]
    for command in commands { #expect(!command.mayRetry, "\(command)") }
    for mode: Bool? in [true, false, nil] {
      #expect(BridgeCommand.accessibility(.read(pid: 1, options: Self.readOptions(automationMode: mode))).mayRetry)
      #expect(BridgeCommand.accessibility(.readFrontmost(x: 1, y: 2, method: .windowServer, options: Self.readOptions(automationMode: mode))).mayRetry)
    }
    let reads: [BridgeCommand] = [
      .dynamicStore(.snapshot(key: "dns")), .ping, .dns(.list), .proxy(.list), .notifications(.list(bundleID: nil)), .notifications(.delivered(bundleID: "app")),
      .health(.list(bundleID: "app")), .accessibility(.hitTest(x: 1, y: 2, attributes: nil, clientType: .noClient)), .accessibility(.deviceSettingRead("voiceover")), .accessibility(.displays),
    ]
    for command in reads {
      #expect(command.mayRetry, "\(command)")
    }
  }

  @Test
  func responseKeepsFailureOutputAndRequiresMatchingIdentity() throws {
    let request = BridgeRequest(command: .clearPhotos, id: "first")
    let result = BridgeResult(exitCode: 1, answers: [.health(.clear(bundleID: "partial", ok: false, error: nil))])
    let data = try BridgeResponse(request: request, result: result).encoded()
    #expect(try BridgeResponse.decode(data, for: request).result == result)
    let other = BridgeRequest(command: .clearPhotos, id: "second")
    #expect(throws: BridgeProtocolError.mismatchedResponse) { try BridgeResponse.decode(data, for: other) }
  }

  @Test
  func binaryPropertyListsSurviveResponseEncodingWithoutJSONCoercion() throws {
    let value: [String: Any] = ["present": true, "value": [Data([0, 255]), Date(timeIntervalSince1970: 1234)]]
    let bytes = try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
    let request = BridgeRequest(command: .dynamicStore(.snapshot(key: "dns")))
    let result = BridgeResult(exitCode: 0, propertyList: bytes)
    #expect(try BridgeResponse.decode(BridgeResponse(request: request, result: result).encoded(), for: request).result == result)
    let propertyList = try #require(result.propertyList)
    #expect(try PropertyListSerialization.propertyList(from: propertyList, options: [], format: nil) as? NSDictionary == value as NSDictionary)
  }

  // An accessibility answer travels as an object in the frame, shaped as its model encodes it, with nothing saying which
  // verb it answers: the request says that, so a frame decodes typed only against the request it answers.
  @Test
  func anAccessibilityAnswerTravelsAsItsOwnShape() throws {
    let request = BridgeRequest(
      command: .accessibility(
        .read(
          pid: 3,
          options: BridgeAXReadOptions(
            maxDepth: 1, maxNodes: 1, attributes: nil, explainUnreachable: false, traversal: .viewHierarchy, automationMode: nil,
            clientType: .noClient))), id: "fixture")
    var node = BridgeAXNode()
    node.label = .string("Settings")
    let result = BridgeResult(exitCode: 0, accessibility: .tree(BridgeAXTreeResponse(tree: node, pid: 3, truncated: false)))
    let frame = try BridgeResponse(request: request, result: result).encoded()

    let wire = try #require(try JSONSerialization.jsonObject(with: frame) as? [String: Any])
    let answer = try #require((wire["result"] as? [String: Any])?["accessibility"] as? NSDictionary)
    #expect(answer == ["ok": true, "pid": 3, "truncated": false, "tree": ["XC_kAXXCAttributeLabel": "Settings"]])
    #expect(try BridgeResponse.decode(frame, for: request).result == result)
    #expect(throws: (any Error).self, "without its request the answer's type is unknown") {
      try JSONDecoder().decode(BridgeResponse.self, from: frame)
    }
  }

  // A connection checks a response is the one it is waiting for without decoding the answer, which the caller decodes.
  @Test
  func aResponseIsCheckedAgainstItsRequestWithoutDecodingItsAnswer() throws {
    let request = BridgeRequest(command: .accessibility(.displays), id: "fixture")
    let frame = Data(#"{"version":5,"id":"fixture","result":{"exitCode":0,"answers":[],"accessibility":{"ok":true,"displays":"not an inventory"}}}"#.utf8)
    try BridgeResponse.validate(frame, for: request)
    #expect(throws: (any Error).self, "the answer itself does not decode") { try BridgeResponse.decode(frame, for: request) }
    #expect(throws: BridgeProtocolError.mismatchedResponse) {
      try BridgeResponse.validate(frame, for: BridgeRequest(command: .accessibility(.displays), id: "other"))
    }
    #expect(throws: BridgeProtocolError.unsupportedVersion(6)) {
      try BridgeResponse.validate(Data(#"{"version":6,"id":"fixture","result":{}}"#.utf8), for: request)
    }
  }

  // Version 4 carried accessibility answers as typed objects; version 5 carries every other service's answers typed.
  @Test
  func theProtocolIsAtTheVersionThatCarriesTypedAccessibilityAnswers() {
    #expect(BridgeRequest.currentVersion == 5)
  }

  @Test
  func rejectsUnsupportedVersionsAndMalformedRequests() throws {
    let request = BridgeRequest(command: .ping)
    var object = try #require(JSONSerialization.jsonObject(with: request.encoded()) as? [String: Any])
    object["version"] = BridgeRequest.currentVersion + 1
    #expect(throws: BridgeProtocolError.unsupportedVersion(BridgeRequest.currentVersion + 1)) { try BridgeRequest.decode(JSONSerialization.data(withJSONObject: object)) }
    for text in ["", "null", "[]", "{}", "{", "{\"version\":3,\"id\":\"x\",\"command\":{\"future\":{}}}"] {
      #expect(throws: (any Error).self, "\(text)") { try BridgeRequest.decode(Data(text.utf8)) }
    }
    for text in ["", "null", "[]", "{}", "{"] {
      #expect(BridgeRequest.identity(of: Data(text.utf8)) == nil, "\(text)")
    }
    // A newer peer's command shape is a version gap, not a malformed request.
    #expect(throws: BridgeProtocolError.unsupportedVersion(6)) { try BridgeRequest.decode(Data(#"{"version":6,"id":"x","command":{"future":{}}}"#.utf8)) }
    #expect(BridgeRequest.identity(of: Data(#"{"version":5,"id":"x","command":{"future":{}}}"#.utf8)) == "x")
    #expect(BridgeRequest.identity(of: Data(#"{"version":5,"id":"x"}"#.utf8)) == "x")
    #expect(BridgeRequest.identity(of: Data(#"{"version":5,"id":7,"command":{"ping":{}}}"#.utf8)) == nil)
  }

  @Test
  func literalWireFixturesPinEveryTopLevelCommand() throws {
    // The synthesized `_0` payload keys are the wire contract the Python harness and older guests
    // speak; a label or case rename here must fail this test rather than the peer.
    let fixtures: [(String, BridgeCommand)] = [
      (#"{"clearContacts":{}}"#, .clearContacts),
      (#"{"clearPhotos":{}}"#, .clearPhotos),
      (#"{"dns":{"_0":{"list":{}}}}"#, .dns(.list)),
      (#"{"dns":{"_0":{"set":{"servers":["::1"]}}}}"#, .dns(.set(servers: ["::1"]))),
      (#"{"dynamicStore":{"_0":{"snapshot":{"key":"k"}}}}"#, .dynamicStore(.snapshot(key: "k"))),
      // `Data` travels as base64, which the Python harness encodes itself.
      (#"{"dynamicStore":{"_0":{"restore":{"key":"k","snapshot":"AP8="}}}}"#, .dynamicStore(.restore(key: "k", snapshot: Data([0, 255])))),
      (#"{"proxy":{"_0":{"set":{"host":"::1","kind":"socks","port":1080}}}}"#, .proxy(.set(host: "::1", port: 1080, kind: .socks))),
      (#"{"notifications":{"_0":{"list":{}}}}"#, .notifications(.list(bundleID: nil))),
      (#"{"notifications":{"_0":{"delivered":{"bundleID":"app"}}}}"#, .notifications(.delivered(bundleID: "app"))),
      (#"{"notifications":{"_0":{"clearDelivered":{"bundleID":"app"}}}}"#, .notifications(.clearDelivered(bundleID: "app"))),
      (#"{"health":{"_0":{"approve":{"bundleID":"app","typeIDs":["step"]}}}}"#, .health(.approve(bundleID: "app", typeIDs: ["step"]))),
      (#"{"accessibility":{"_0":{"clientType":0,"maxDepth":5,"maxNodes":10,"pid":42,"traversal":"view-hierarchy","verb":"describe"}}}"#, .accessibility(.read(pid: 42, options: Self.readOptions(maxDepth: 5, maxNodes: 10)))),
      (#"{"accessibility":{"_0":{"clientType":0,"verb":"hittest","x":1.5,"y":2}}}"#, .accessibility(.hitTest(x: 1.5, y: 2, attributes: nil, clientType: .noClient))),
      (#"{"ping":{}}"#, .ping),
      (#"{"shutdown":{}}"#, .shutdown),
    ]
    for (text, command) in fixtures {
      let literal = #"{"command":"# + text + #","id":"fixture","version":5}"#
      #expect(try BridgeRequest.decode(Data(literal.utf8)).command == command, "\(text)")
      #expect(String(decoding: try BridgeRequest(command: command, id: "fixture").encoded(), as: UTF8.self) == literal, "\(text)")
    }
  }

  @Test
  func literalWireFixturesAndResponseVersionBoundary() throws {
    let request = try BridgeRequest.decode(Data(#"{"version":5,"id":"fixture","command":{"dns":{"_0":{"set":{"servers":["::1","1.1.1.1"]}}}}}"#.utf8))
    #expect(request.command == .dns(.set(servers: ["::1", "1.1.1.1"])))
    let success = Data(
      #"{"version":5,"id":"fixture","result":{"exitCode":0,"answers":[{"health":{"_0":{"action":"clear","bundleID":"app","error":null,"ok":true}}}]}}"#.utf8)
    #expect(try BridgeResponse.decode(success, for: request).result == BridgeResult(exitCode: 0, answers: [.health(.clear(bundleID: "app", ok: true, error: nil))]))
    let future = Data(#"{"version":6,"id":"fixture","result":{"exitCode":0,"answers":[]}}"#.utf8)
    #expect(throws: BridgeProtocolError.unsupportedVersion(6)) { try BridgeResponse.decode(future, for: request) }
    for text in [#"{"version":5,"result":{"exitCode":0,"answers":[]}}"#, #"{"version":5,"id":"different","result":{"exitCode":0,"answers":[]}}"#] {
      #expect(throws: BridgeProtocolError.mismatchedResponse) { try BridgeResponse.decode(Data(text.utf8), for: request) }
    }
  }
}

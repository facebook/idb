/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
@_implementationOnly import SimulatorFrameworkBridgeProtocol
import XCTest

final class BridgeProtocolTests: XCTestCase {
  func testEveryServiceUsesTheSameRequestForArgumentsAndFrames() throws {
    let commands: [BridgeCommand] = [
      .clearContacts, .clearPhotos,
      .dns(.list), .dns(.set(servers: ["1.1.1.1", "::1"])), .dns(.clear),
      .proxy(.list), .proxy(.set(host: "localhost", port: 8080, kind: .http)),
      .proxy(.set(host: "::1", port: 1080, kind: .socks)), .proxy(.clear),
      .notifications(.list(bundleID: nil)), .notifications(.list(bundleID: "com.example.app")),
      .notifications(.approve(bundleID: "com.example.app")), .notifications(.revoke(bundleID: "com.example.app")),
      .notifications(.delivered(bundleID: "com.example.app")), .notifications(.clearDelivered(bundleID: "com.example.app")),
      .health(.list(bundleID: "com.example.app")), .health(.clear(bundleID: "com.example.app")),
      .health(.approve(bundleID: "com.example.app", typeIDs: ["step"])),
      .health(.revoke(bundleID: "com.example.app", typeIDs: [])),
      .accessibility(["verb": .string("describe"), "pid": .integer(42), "automationMode": .bool(false)]),
      .ping, .shutdown,
    ]
    for command in commands {
      let request = BridgeRequest(command: command, id: "request-1")
      let arguments = try request.arguments
      XCTAssertEqual(arguments.count, 2)
      XCTAssertEqual(arguments[0], "rpc")
      let data = Data(arguments[1].utf8)
      XCTAssertEqual(try BridgeRequest.decode(data), request)
      XCTAssertEqual(try BridgeFrame.size(fromHeader: BridgeFrame.header(forSize: data.count)), data.count)
      XCTAssertEqual(try request.encoded(), data)
    }
  }

  func testMutationsCannotBeRetried() {
    let commands: [BridgeCommand] = [
      .clearContacts, .clearPhotos, .dns(.clear), .dns(.set(servers: [])), .proxy(.clear),
      .proxy(.set(host: "localhost", port: 8080, kind: .http)),
      .notifications(.approve(bundleID: "app")), .notifications(.revoke(bundleID: "app")),
      .notifications(.clearDelivered(bundleID: "app")),
      .health(.approve(bundleID: "app", typeIDs: [])), .health(.revoke(bundleID: "app", typeIDs: [])),
      .health(.clear(bundleID: "app")), .shutdown,
      .accessibility(["verb": .string("perform")]), .accessibility(["verb": .string("setvalue")]),
      .accessibility(["verb": .string("settings-set")]), .accessibility(["verb": .string("unknown")]),
      .accessibility([:]),
    ]
    for command in commands { XCTAssertFalse(command.mayRetry, "\(command)") }
    for mode: BridgeJSONValue in [.bool(true), .bool(false), .null] {
      XCTAssertTrue(BridgeCommand.accessibility(["verb": .string("describe"), "automationMode": mode]).mayRetry)
      XCTAssertTrue(BridgeCommand.accessibility(["verb": .string("hittest"), "automationMode": mode]).mayRetry)
      XCTAssertFalse(BridgeCommand.accessibility(["verb": .string("perform"), "automationMode": mode]).mayRetry)
    }
    let reads: [BridgeCommand] = [.ping, .dns(.list), .proxy(.list), .notifications(.list(bundleID: nil)), .notifications(.delivered(bundleID: "app")), .health(.list(bundleID: "app")), .accessibility(["verb": .string("describe")])]
    for command in reads {
      XCTAssertTrue(command.mayRetry, "\(command)")
    }
  }

  func testResponseKeepsFailureOutputAndRequiresMatchingIdentity() throws {
    let request = BridgeRequest(command: .clearPhotos, id: "first")
    let result = BridgeResult(exitCode: 1, values: [.object(["partial": .bool(true)])])
    let data = try BridgeResponse(request: request, result: result).encoded()
    XCTAssertEqual(try BridgeResponse.decode(data, for: request).result, result)
    let other = BridgeRequest(command: .clearPhotos, id: "second")
    XCTAssertThrowsError(try BridgeResponse.decode(data, for: other)) {
      XCTAssertEqual($0 as? BridgeProtocolError, .mismatchedResponse)
    }
  }

  func testRejectsUnsupportedVersionsAndMalformedRequests() throws {
    let request = BridgeRequest(command: .ping)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: request.encoded()) as? [String: Any])
    object["version"] = 2
    XCTAssertThrowsError(try BridgeRequest.decode(JSONSerialization.data(withJSONObject: object))) {
      XCTAssertEqual($0 as? BridgeProtocolError, .unsupportedVersion(2))
    }
    for text in ["", "null", "[]", "{}", "{", "{\"version\":1,\"id\":\"x\",\"command\":{\"future\":{}}}"] {
      XCTAssertThrowsError(try BridgeRequest.decode(Data(text.utf8)), text)
    }
    for text in ["", "null", "[]", "{}", "{"] {
      XCTAssertNil(BridgeRequest.identity(of: Data(text.utf8)), text)
    }
    // A newer peer's command shape is a version gap, not a malformed request.
    XCTAssertThrowsError(try BridgeRequest.decode(Data(#"{"version":2,"id":"x","command":{"future":{}}}"#.utf8))) {
      XCTAssertEqual($0 as? BridgeProtocolError, .unsupportedVersion(2))
    }
    XCTAssertEqual(BridgeRequest.identity(of: Data(#"{"version":1,"id":"x","command":{"future":{}}}"#.utf8)), "x")
    XCTAssertEqual(BridgeRequest.identity(of: Data(#"{"version":2,"id":"x"}"#.utf8)), "x")
    XCTAssertNil(BridgeRequest.identity(of: Data(#"{"version":1,"id":7,"command":{"ping":{}}}"#.utf8)))
  }

  func testLiteralWireFixturesPinEveryTopLevelCommand() throws {
    // The synthesized `_0` payload keys are the wire contract the Python harness and older guests
    // speak; a label or case rename here must fail this test rather than the peer.
    let fixtures: [(String, BridgeCommand)] = [
      (#"{"clearContacts":{}}"#, .clearContacts),
      (#"{"clearPhotos":{}}"#, .clearPhotos),
      (#"{"dns":{"_0":{"list":{}}}}"#, .dns(.list)),
      (#"{"dns":{"_0":{"set":{"servers":["::1"]}}}}"#, .dns(.set(servers: ["::1"]))),
      (#"{"proxy":{"_0":{"set":{"host":"::1","kind":"socks","port":1080}}}}"#, .proxy(.set(host: "::1", port: 1080, kind: .socks))),
      (#"{"notifications":{"_0":{"list":{}}}}"#, .notifications(.list(bundleID: nil))),
      (#"{"notifications":{"_0":{"delivered":{"bundleID":"app"}}}}"#, .notifications(.delivered(bundleID: "app"))),
      (#"{"notifications":{"_0":{"clearDelivered":{"bundleID":"app"}}}}"#, .notifications(.clearDelivered(bundleID: "app"))),
      (#"{"health":{"_0":{"approve":{"bundleID":"app","typeIDs":["step"]}}}}"#, .health(.approve(bundleID: "app", typeIDs: ["step"]))),
      (#"{"accessibility":{"_0":{"pid":42,"verb":"describe"}}}"#, .accessibility(["verb": .string("describe"), "pid": .integer(42)])),
      (#"{"ping":{}}"#, .ping),
      (#"{"shutdown":{}}"#, .shutdown),
    ]
    for (text, command) in fixtures {
      let literal = #"{"command":"# + text + #","id":"fixture","version":1}"#
      XCTAssertEqual(try BridgeRequest.decode(Data(literal.utf8)).command, command, text)
      XCTAssertEqual(String(decoding: try BridgeRequest(command: command, id: "fixture").encoded(), as: UTF8.self), literal, text)
    }
  }

  func testIntegersAndBooleansSurviveJSONWithoutLosingPrecision() throws {
    let value = BridgeJSONValue.object([
      "signed": .integer(Int64.min), "unsigned": .unsignedInteger(UInt64.max),
      "aboveDoublePrecision": .integer(9_007_199_254_740_993),
      "bool": .bool(true), "number": .integer(1), "fraction": .number(1.25),
      "nested": .array([.null, .string("quotes\" newline\n NUL\0")]),
    ])
    let data = try JSONEncoder().encode(value)
    XCTAssertEqual(try JSONDecoder().decode(BridgeJSONValue.self, from: data), value)
    XCTAssertEqual(try BridgeJSONValue(foundationValue: value.foundationValue), value)
    XCTAssertEqual(try BridgeJSONValue(foundationValue: NSNumber(value: true)), .bool(true))
    XCTAssertEqual(try BridgeJSONValue(foundationValue: NSNumber(value: 1)), .integer(1))
    XCTAssertThrowsError(try BridgeJSONValue(foundationValue: NSNumber(value: Double.nan)))
    XCTAssertThrowsError(try BridgeJSONValue(foundationValue: Date()))
  }

  func testFoundationJSONPreservesLargeIntegerAndExponentValues() throws {
    let object: [String: Any] = [
      "large": NSNumber(value: Int64(9_007_199_254_740_993)),
      "signedMax": NSNumber(value: Int64.max),
      "unsignedMax": NSNumber(value: UInt64.max),
      "twoTo63": NSNumber(value: Double(9_223_372_036_854_775_808)),
      "twoTo64": NSNumber(value: Double(18_446_744_073_709_551_616)),
    ]
    let bytes = try JSONSerialization.data(withJSONObject: object)
    XCTAssertEqual(try BridgeJSONValue(foundationValue: JSONSerialization.jsonObject(with: bytes)), try BridgeJSONValue(foundationValue: object))
    let value = try JSONDecoder().decode(BridgeJSONValue.self, from: Data("[1e3,1.25e-2,-0.0,9007199254740993]".utf8))
    XCTAssertEqual(value, .array([.integer(1000), .number(0.0125), .integer(0), .integer(9_007_199_254_740_993)]))
  }

  func testNumericRepresentationsHaveJSONEqualityWithoutRoundingLargeIntegers() throws {
    for value: BridgeJSONValue in [.unsignedInteger(1), .number(1), .number(-0.0), .unsignedInteger(UInt64.max)] {
      XCTAssertEqual(try JSONDecoder().decode(BridgeJSONValue.self, from: JSONEncoder().encode(value)), value)
    }
    XCTAssertEqual(BridgeJSONValue.integer(1), .number(1))
    XCTAssertEqual(BridgeJSONValue.integer(0), .number(-0.0))
    XCTAssertNotEqual(BridgeJSONValue.integer(1), .bool(true))
    XCTAssertNotEqual(BridgeJSONValue.integer(9_007_199_254_740_993), .number(9_007_199_254_740_992))
    XCTAssertNotEqual(BridgeJSONValue.unsignedInteger(UInt64.max), .unsignedInteger(UInt64.max - 1))
    for value in [Double.nan, Double.infinity, -Double.infinity] {
      XCTAssertThrowsError(try JSONEncoder().encode(BridgeJSONValue.number(value)))
    }
  }

  func testLiteralWireFixturesAndResponseVersionBoundary() throws {
    let request = try BridgeRequest.decode(Data(#"{"version":1,"id":"fixture","command":{"dns":{"_0":{"set":{"servers":["::1","1.1.1.1"]}}}}}"#.utf8))
    XCTAssertEqual(request.command, .dns(.set(servers: ["::1", "1.1.1.1"])))
    let success = Data(#"{"version":1,"id":"fixture","result":{"exitCode":0,"values":[{"ok":true},null,42]}}"#.utf8)
    XCTAssertEqual(try BridgeResponse.decode(success, for: request).result, BridgeResult(exitCode: 0, values: [.object(["ok": .bool(true)]), .null, .integer(42)]))
    let future = Data(#"{"version":2,"id":"fixture","result":{"exitCode":0,"values":[]}}"#.utf8)
    XCTAssertThrowsError(try BridgeResponse.decode(future, for: request)) {
      XCTAssertEqual($0 as? BridgeProtocolError, .unsupportedVersion(2))
    }
    for text in [#"{"version":1,"result":{"exitCode":0,"values":[]}}"#, #"{"version":1,"id":"different","result":{"exitCode":0,"values":[]}}"#] {
      XCTAssertThrowsError(try BridgeResponse.decode(Data(text.utf8), for: request)) {
        XCTAssertEqual($0 as? BridgeProtocolError, .mismatchedResponse)
      }
    }
  }

  func testFrameBoundsAreIdenticalInBothDirections() throws {
    XCTAssertEqual(try BridgeFrame.header(forSize: 258), Data([0, 0, 1, 2]))
    for size in [1, BridgeFrame.maximumSize] {
      XCTAssertEqual(try BridgeFrame.size(fromHeader: BridgeFrame.header(forSize: size)), size)
    }
    for size in [0, -1, BridgeFrame.maximumSize + 1] {
      XCTAssertThrowsError(try BridgeFrame.header(forSize: size))
    }
    for header in [Data(), Data([0, 0, 0]), Data([0, 0, 0, 0]), Data([1, 0, 0, 1]), Data([255, 255, 255, 255])] {
      XCTAssertThrowsError(try BridgeFrame.size(fromHeader: header))
    }
  }
}

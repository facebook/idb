/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import XCTest
import XCTestBootstrap

/// A stand-in for the daemon's `XCAccessibilityElement`. The point-read owning pid is read off the
/// returned element via an `@objc processIdentifier` message (the session `unsafeBitCast`s the handle
/// to a module-local protocol), so the fake element must answer that selector.
private final class FakeAXElement: NSObject {
  @objc let processIdentifier: CInt
  init(processIdentifier: CInt) { self.processIdentifier = processIdentifier }
}

/// A fake `RemoteInvoking` that records the order of the typed operations and returns canned
/// values, so `FBRemoteAutomationSession`'s handshake ordering, capability parsing, and
/// connect-then-operate behaviour can be tested without a live DTX connection.
private actor FakeRemoteInvoker: RemoteInvoking {

  enum Call: String, Equatable {
    case beginSession
    case exchangeCapabilities
    case loadAccessibility
    case synthesizeEvent
    case requestElement
    case fetchAttributes
    case setAttribute
    case performDeviceEvent
  }

  enum FakeError: Error { case injected }

  private(set) var calls: [Call] = []
  private(set) var lastPointX: Double?
  private(set) var lastPointY: Double?
  private(set) var lastImplicitConfirmationInterval: TimeInterval?
  private(set) var lastAttributes: [String]?
  private(set) var lastSetValue: String?

  private let cannedCapabilities: [String: Int]
  private var beginSessionFailuresRemaining: Int
  private let cannedPid: CInt

  init(capabilities: [String: Int] = [:], beginSessionFailures: Int = 0, pid: CInt = 1320) {
    self.cannedCapabilities = capabilities
    self.beginSessionFailuresRemaining = beginSessionFailures
    self.cannedPid = pid
  }

  func callLog() -> [Call] { calls }

  func beginSession(clientProtocolVersion: Int, deadline: TimeInterval) async throws {
    calls.append(.beginSession)
    if beginSessionFailuresRemaining > 0 {
      beginSessionFailuresRemaining -= 1
      throw FakeError.injected
    }
  }

  func exchangeCapabilities(deadline: TimeInterval) async throws -> sending Any? {
    calls.append(.exchangeCapabilities)
    return cannedCapabilities as NSDictionary
  }

  func loadAccessibility(timeout: TimeInterval, deadline: TimeInterval) async throws {
    calls.append(.loadAccessibility)
  }

  func synthesizeEvent(_ record: sending Any, implicitConfirmationInterval: TimeInterval, deadline: TimeInterval) async throws {
    calls.append(.synthesizeEvent)
    lastImplicitConfirmationInterval = implicitConfirmationInterval
  }

  func requestElement(atPoint point: sending Any, deadline: TimeInterval) async throws -> sending Any? {
    calls.append(.requestElement)
    if let dictionary = point as? NSDictionary, let decoded = CGPoint(dictionaryRepresentation: dictionary as CFDictionary) {
      lastPointX = decoded.x
      lastPointY = decoded.y
    }
    return FakeAXElement(processIdentifier: cannedPid)
  }

  func fetchAttributes(_ attributes: sending Any, forElement element: sending Any, deadline: TimeInterval) async throws -> sending Any? {
    calls.append(.fetchAttributes)
    lastAttributes = attributes as? [String]
    return ["attributes": "value"] as NSDictionary
  }

  func setAttribute(_ attribute: sending Any, value: sending Any, forElement element: sending Any, deadline: TimeInterval) async throws {
    calls.append(.setAttribute)
    lastSetValue = value as? String
  }

  func performDeviceEvent(_ event: sending Any, deadline: TimeInterval) async throws {
    calls.append(.performDeviceEvent)
  }
}

final class FBRemoteAutomationSessionTests: XCTestCase {

  // MARK: - Handshake

  func testConnected_RunsHandshakeInOrder() async throws {
    let invoker = FakeRemoteInvoker()
    _ = try await FBRemoteAutomationSession.connected(invoker: invoker, processIdentifier: 123)

    let calls = await invoker.callLog()
    XCTAssertEqual(calls, [.beginSession, .exchangeCapabilities, .loadAccessibility], "connected(invoker:) must run the handshake as beginSession -> exchangeCapabilities -> loadAccessibility, in that order.")
  }

  func testConnected_HandshakeFailure_Throws() async throws {
    let invoker = FakeRemoteInvoker(beginSessionFailures: 1)

    do {
      _ = try await FBRemoteAutomationSession.connected(invoker: invoker, processIdentifier: 1)
      XCTFail("connected(invoker:) must surface a handshake failure and yield no session.")
    } catch {
      // Expected — the caller memoizes the session, so it discards the failure and reconnects later.
    }

    let calls = await invoker.callLog()
    XCTAssertEqual(calls, [.beginSession], "A handshake that fails at beginSession must not proceed to the rest of the handshake.")
  }

  func testSetValue_RequestsElementThenSetsAttribute() async throws {
    let invoker = FakeRemoteInvoker()
    let session = try await FBRemoteAutomationSession.connected(invoker: invoker, processIdentifier: 1)

    try await session.setValue("hello", atX: 10, y: 20, valueAttribute: "XC_kAXXCAttributeValue")

    let calls = await invoker.callLog()
    XCTAssertTrue(calls.contains(.requestElement))
    XCTAssertTrue(calls.contains(.setAttribute))
    let lastSetValue = await invoker.lastSetValue
    XCTAssertEqual(lastSetValue, "hello")
  }

  // MARK: - Capabilities

  func testCapabilities_ParsedFromExchange() async throws {
    let invoker = FakeRemoteInvoker(capabilities: ["synthesizeEvent": 1, "requestElement": 3])
    let session = try await FBRemoteAutomationSession.connected(invoker: invoker, processIdentifier: 1)

    let capabilities = await session.capabilities
    XCTAssertTrue(capabilities.supports("synthesizeEvent"), "A capability present at version 1 must be reported as supported at the default minimum.")
    XCTAssertTrue(capabilities.supports("requestElement", minimumVersion: 3), "A capability must be supported at its advertised version.")
    XCTAssertFalse(capabilities.supports("requestElement", minimumVersion: 4), "A capability must not be supported above its advertised version.")
    XCTAssertFalse(capabilities.supports("missing"), "An unadvertised capability must be unsupported.")
  }

  // MARK: - Connect-then-operate

  func testRequestElement_ConvertsPointToPoints() async throws {
    let invoker = FakeRemoteInvoker()
    let session = try await FBRemoteAutomationSession.connected(invoker: invoker, processIdentifier: 1)

    _ = try await session.requestElement(atX: 42.5, y: 99.0)

    let calls = await invoker.callLog()
    XCTAssertEqual(calls, [.beginSession, .exchangeCapabilities, .loadAccessibility, .requestElement], "A read on a connected session issues only the read — the handshake already ran at construction.")
    let x = await invoker.lastPointX
    let y = await invoker.lastPointY
    XCTAssertEqual(x, 42.5, "The point must be forwarded as a point dictionary carrying the exact x coordinate.")
    XCTAssertEqual(y, 99.0, "The point must be forwarded as a point dictionary carrying the exact y coordinate.")
  }

  func testPerformDeviceEvent_Forwards() async throws {
    let invoker = FakeRemoteInvoker()
    let session = try await FBRemoteAutomationSession.connected(invoker: invoker, processIdentifier: 1)

    try await session.performDeviceEvent(page: 0x0C, usage: 0x40, duration: 0)

    let calls = await invoker.callLog()
    XCTAssertEqual(calls, [.beginSession, .exchangeCapabilities, .loadAccessibility, .performDeviceEvent], "A device event on a connected session issues only the device event.")
  }

  func testSynthesizeEvent_ForwardsInterval() async throws {
    let invoker = FakeRemoteInvoker()
    let session = try await FBRemoteAutomationSession.connected(invoker: invoker, processIdentifier: 1)

    try await session.synthesizeEvent(NSObject(), implicitConfirmationInterval: 0.25)

    let calls = await invoker.callLog()
    XCTAssertEqual(calls, [.beginSession, .exchangeCapabilities, .loadAccessibility, .synthesizeEvent], "A write on a connected session issues only the write.")
    let interval = await invoker.lastImplicitConfirmationInterval
    XCTAssertEqual(interval, 0.25, "The implicit confirmation interval must be forwarded unchanged.")
  }

  func testFetchAttributes_ForwardsAttributes() async throws {
    let invoker = FakeRemoteInvoker()
    let session = try await FBRemoteAutomationSession.connected(invoker: invoker, processIdentifier: 1)

    _ = try await session.fetchAttributes(["AXLabel", "AXValue"], forElement: NSObject())

    let calls = await invoker.callLog()
    XCTAssertEqual(calls, [.beginSession, .exchangeCapabilities, .loadAccessibility, .fetchAttributes], "A read on a connected session issues only the read.")
    let attributes = await invoker.lastAttributes
    XCTAssertEqual(attributes, ["AXLabel", "AXValue"], "The requested attribute names must be forwarded unchanged and in order.")
  }

  func testElementAttributes_ReturnsAttributesAndOwningPid() async throws {
    let invoker = FakeRemoteInvoker(pid: 4321)
    let session = try await FBRemoteAutomationSession.connected(invoker: invoker, processIdentifier: 1)

    let hit = try await session.elementAttributes(atX: 5, y: 6, attributes: ["AXLabel"])

    let result = try XCTUnwrap(hit, "A point read that resolves an element must return its attributes and owning pid.")
    XCTAssertEqual(result.pid, 4321, "The owning pid must be read off the hit element and returned alongside its attributes.")
    XCTAssertEqual(result.attributes["attributes"] as? String, "value", "The element's fetched attribute dictionary must be returned.")

    let calls = await invoker.callLog()
    XCTAssertEqual(calls, [.beginSession, .exchangeCapabilities, .loadAccessibility, .requestElement, .fetchAttributes], "A point read resolves the element then fetches its attributes.")
  }
}

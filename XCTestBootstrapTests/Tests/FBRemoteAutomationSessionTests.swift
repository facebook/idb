/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import XCTest
import XCTestBootstrap

/// A fake `RemoteInvoking` that records the order of the typed operations and returns canned
/// values, so `FBRemoteAutomationSession`'s handshake ordering, memoization, retry, capability
/// parsing, and prime-before-op behaviour can be tested without a live DTX connection.
private actor FakeRemoteInvoker: RemoteInvoking {

  enum Call: String, Equatable {
    case beginSession
    case exchangeCapabilities
    case loadAccessibility
    case synthesizeEvent
    case requestElement
    case fetchAttributes
    case setAttribute
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

  init(capabilities: [String: Int] = [:], beginSessionFailures: Int = 0) {
    self.cannedCapabilities = capabilities
    self.beginSessionFailuresRemaining = beginSessionFailures
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
    return ["type": "element"] as NSDictionary
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
}

final class FBRemoteAutomationSessionTests: XCTestCase {

  // MARK: - Handshake ordering & memoization

  func testPrime_RunsHandshakeInOrder() async throws {
    let invoker = FakeRemoteInvoker()
    let session = FBRemoteAutomationSession(invoker: invoker, processIdentifier: 123)

    try await session.prime()

    let calls = await invoker.callLog()
    XCTAssertEqual(calls, [.beginSession, .exchangeCapabilities, .loadAccessibility], "prime() must run the handshake as beginSession -> exchangeCapabilities -> loadAccessibility, in that order.")
  }

  func testSetValue_RequestsElementThenSetsAttribute() async throws {
    let invoker = FakeRemoteInvoker()
    let session = FBRemoteAutomationSession(invoker: invoker, processIdentifier: 1)

    try await session.setValue("hello", atX: 10, y: 20, valueAttribute: "XC_kAXXCAttributeValue")

    let calls = await invoker.callLog()
    XCTAssertTrue(calls.contains(.requestElement))
    XCTAssertTrue(calls.contains(.setAttribute))
    let lastSetValue = await invoker.lastSetValue
    XCTAssertEqual(lastSetValue, "hello")
  }

  func testPrime_IsMemoized_HandshakeRunsOnce() async throws {
    let invoker = FakeRemoteInvoker()
    let session = FBRemoteAutomationSession(invoker: invoker, processIdentifier: 1)

    try await session.prime()
    try await session.prime()

    let calls = await invoker.callLog()
    XCTAssertEqual(calls, [.beginSession, .exchangeCapabilities, .loadAccessibility], "A second prime() must not re-run the handshake.")
  }

  func testPrime_Failure_ClearsMemo_AllowingRetry() async throws {
    let invoker = FakeRemoteInvoker(beginSessionFailures: 1)
    let session = FBRemoteAutomationSession(invoker: invoker, processIdentifier: 1)

    do {
      try await session.prime()
      XCTFail("The first prime() must surface the injected handshake failure.")
    } catch {
      // expected
    }

    try await session.prime()

    let calls = await invoker.callLog()
    XCTAssertEqual(calls.filter { $0 == .beginSession }.count, 2, "A failed handshake must clear the memo so a later prime() retries beginSession.")
    XCTAssertEqual(Array(calls.suffix(3)), [.beginSession, .exchangeCapabilities, .loadAccessibility], "The retry must complete the full handshake.")
  }

  // MARK: - Capabilities

  func testCapabilities_EmptyUntilPrimed() async {
    let invoker = FakeRemoteInvoker(capabilities: ["synthesizeEvent": 1])
    let session = FBRemoteAutomationSession(invoker: invoker, processIdentifier: 1)

    let capabilities = await session.capabilities
    XCTAssertEqual(capabilities, .empty, "Capabilities must be empty before the handshake exchanges them.")
  }

  func testCapabilities_ParsedFromExchange() async throws {
    let invoker = FakeRemoteInvoker(capabilities: ["synthesizeEvent": 1, "requestElement": 3])
    let session = FBRemoteAutomationSession(invoker: invoker, processIdentifier: 1)

    try await session.prime()

    let capabilities = await session.capabilities
    XCTAssertTrue(capabilities.supports("synthesizeEvent"), "A capability present at version 1 must be reported as supported at the default minimum.")
    XCTAssertTrue(capabilities.supports("requestElement", minimumVersion: 3), "A capability must be supported at its advertised version.")
    XCTAssertFalse(capabilities.supports("requestElement", minimumVersion: 4), "A capability must not be supported above its advertised version.")
    XCTAssertFalse(capabilities.supports("missing"), "An unadvertised capability must be unsupported.")
  }

  // MARK: - Prime-before-op

  func testRequestElement_PrimesThenConvertsPointToPoints() async throws {
    let invoker = FakeRemoteInvoker()
    let session = FBRemoteAutomationSession(invoker: invoker, processIdentifier: 1)

    _ = try await session.requestElement(atX: 42.5, y: 99.0)

    let calls = await invoker.callLog()
    XCTAssertEqual(calls, [.beginSession, .exchangeCapabilities, .loadAccessibility, .requestElement], "requestElement must prime the handshake before issuing the read.")
    let x = await invoker.lastPointX
    let y = await invoker.lastPointY
    XCTAssertEqual(x, 42.5, "The point must be forwarded as a point dictionary carrying the exact x coordinate.")
    XCTAssertEqual(y, 99.0, "The point must be forwarded as a point dictionary carrying the exact y coordinate.")
  }

  func testSynthesizeEvent_PrimesThenForwardsInterval() async throws {
    let invoker = FakeRemoteInvoker()
    let session = FBRemoteAutomationSession(invoker: invoker, processIdentifier: 1)

    try await session.synthesizeEvent(NSObject(), implicitConfirmationInterval: 0.25)

    let calls = await invoker.callLog()
    XCTAssertEqual(calls, [.beginSession, .exchangeCapabilities, .loadAccessibility, .synthesizeEvent], "synthesizeEvent must prime the handshake before issuing the write.")
    let interval = await invoker.lastImplicitConfirmationInterval
    XCTAssertEqual(interval, 0.25, "The implicit confirmation interval must be forwarded unchanged.")
  }

  func testFetchAttributes_PrimesThenForwardsAttributes() async throws {
    let invoker = FakeRemoteInvoker()
    let session = FBRemoteAutomationSession(invoker: invoker, processIdentifier: 1)

    _ = try await session.fetchAttributes(["AXLabel", "AXValue"], forElement: NSObject())

    let calls = await invoker.callLog()
    XCTAssertEqual(calls, [.beginSession, .exchangeCapabilities, .loadAccessibility, .fetchAttributes], "fetchAttributes must prime the handshake before issuing the read.")
    let attributes = await invoker.lastAttributes
    XCTAssertEqual(attributes, ["AXLabel", "AXValue"], "The requested attribute names must be forwarded unchanged and in order.")
  }
}

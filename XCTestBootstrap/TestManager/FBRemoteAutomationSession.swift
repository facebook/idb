/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import Foundation

/// A long-lived, reused session over the guest `testmanagerd` remote-automation channel.
///
/// The channel is unauthenticated and session-less on the simulator, so this drives UI
/// automation with no `.xctest` bundle, runner, or build. Operations are dispatched through
/// an injected `RemoteInvoking`; the real one messages a resumed DTX connection's typed
/// proxy, and tests inject a fake to exercise handshake ordering and payload handling without
/// a live socket.
///
/// One instance per target, memoized and reused. The handshake
/// (`beginSession@1000` -> `exchangeCapabilities` -> settle -> `loadAccessibilityWithTimeout`)
/// runs once, eagerly via `prime()`. `enableAutomationMode` is never sent — it wedges
/// hit-tests. Reads additionally require `ApplicationAccessibilityEnabled=1` set on the
/// target before it launches, which the caller arranges outside this type.
public actor FBRemoteAutomationSession {

  private let invoker: RemoteInvoking
  private let processIdentifier: Int32
  private let handshakeDeadline: TimeInterval
  private let readDeadline: TimeInterval
  private let writeDeadline: TimeInterval

  private var primeTask: Task<Void, Error>?
  private var capabilitiesValue = FBRemoteAutomationCapabilities.empty

  private static let clientProtocolVersion = 1000
  private static let loadAccessibilityTimeout: TimeInterval = 15
  private static let capabilitiesSettleInterval: TimeInterval = 0.4
  private static let accessibilitySettleInterval: TimeInterval = 0.5

  public init(
    invoker: RemoteInvoking,
    processIdentifier: Int32,
    handshakeDeadline: TimeInterval = 30,
    readDeadline: TimeInterval = 20,
    writeDeadline: TimeInterval = 20
  ) {
    self.invoker = invoker
    self.processIdentifier = processIdentifier
    self.handshakeDeadline = handshakeDeadline
    self.readDeadline = readDeadline
    self.writeDeadline = writeDeadline
  }

  /// The capabilities the daemon advertised during the handshake. Empty until primed.
  public var capabilities: FBRemoteAutomationCapabilities {
    capabilitiesValue
  }

  // MARK: - Handshake

  /// Eagerly performs the handshake, idempotently. Concurrent callers await one handshake;
  /// a failed handshake clears the memo so a later call retries.
  public func prime() async throws {
    if let task = primeTask {
      try await task.value
      return
    }
    let task = Task { try await self.performHandshake() }
    primeTask = task
    do {
      try await task.value
    } catch {
      primeTask = nil
      throw error
    }
  }

  private func performHandshake() async throws {
    try await invoker.beginSession(clientProtocolVersion: Self.clientProtocolVersion, deadline: handshakeDeadline)
    let capabilitiesResponse = try await invoker.exchangeCapabilities(deadline: handshakeDeadline)
    capabilitiesValue = FBRemoteAutomationCapabilities.parse(capabilitiesResponse)
    // The daemon needs a beat after exchanging capabilities before accessibility loads.
    try await Task.sleep(nanoseconds: UInt64(Self.capabilitiesSettleInterval * 1_000_000_000))
    try await invoker.loadAccessibility(
      timeout: Self.loadAccessibilityTimeout,
      deadline: handshakeDeadline + Self.loadAccessibilityTimeout
    )
    // Accessibility needs a beat to become queryable after loading; reads issued immediately after
    // `loadAccessibility` return no element.
    try await Task.sleep(nanoseconds: UInt64(Self.accessibilitySettleInterval * 1_000_000_000))
  }

  // MARK: - Writes

  /// Submits a synthesized input event, waiting up to `implicitConfirmationInterval` extra
  /// seconds for the daemon's coarse settle before returning.
  public func synthesizeEvent(_ record: sending Any, implicitConfirmationInterval: TimeInterval = 0) async throws {
    try await prime()
    try await invoker.synthesizeEvent(
      record,
      implicitConfirmationInterval: implicitConfirmationInterval,
      deadline: writeDeadline + implicitConfirmationInterval
    )
  }

  // MARK: - Reads

  /// The application's accessibility root, used as the anchor for `fetchAttributes`.
  public func applicationElement() throws -> sending Any {
    guard let element = FBRemoteAutomationPayloads.applicationElement(forProcessIdentifier: processIdentifier) else {
      throw FBRemoteAutomationError.payloadUnavailable("XCAccessibilityElement")
    }
    return element
  }

  /// The accessibility element at a screen point, expressed in points.
  public func requestElement(atX x: Double, y: Double) async throws -> sending Any? {
    try await prime()
    let point = CGPointCreateDictionaryRepresentation(CGPoint(x: x, y: y)) as NSDictionary
    return try await invoker.requestElement(atPoint: point, deadline: readDeadline)
  }

  /// The requested attributes for an element, as returned by the daemon.
  public func fetchAttributes(_ attributes: [String], forElement element: sending Any) async throws -> sending Any? {
    try await prime()
    return try await invoker.fetchAttributes(attributes as NSArray, forElement: element, deadline: readDeadline)
  }
}

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
/// One instance per target, memoized and reused. It is handed out already-connected via
/// `connected(invoker:…)`, which runs the handshake
/// (`beginSession@1000` -> `exchangeCapabilities` -> settle -> `loadAccessibilityWithTimeout`)
/// exactly once, at construction — operations assume it is complete rather than re-checking per
/// call. `enableAutomationMode` is never sent — it wedges hit-tests. Reads additionally require
/// `ApplicationAccessibilityEnabled=1` set on the target before it launches, which the caller
/// arranges outside this type.
public actor FBRemoteAutomationSession {

  private let invoker: RemoteInvoking
  private let processIdentifier: Int32
  private let handshakeDeadline: TimeInterval
  private let readDeadline: TimeInterval
  private let writeDeadline: TimeInterval

  private var capabilitiesValue = FBRemoteAutomationCapabilities.empty

  private static let clientProtocolVersion = 1000
  private static let loadAccessibilityTimeout: TimeInterval = 15
  private static let capabilitiesSettleInterval: TimeInterval = 0.4
  private static let accessibilitySettleInterval: TimeInterval = 0.5

  private init(
    invoker: RemoteInvoking,
    processIdentifier: Int32,
    handshakeDeadline: TimeInterval,
    readDeadline: TimeInterval,
    writeDeadline: TimeInterval
  ) {
    self.invoker = invoker
    self.processIdentifier = processIdentifier
    self.handshakeDeadline = handshakeDeadline
    self.readDeadline = readDeadline
    self.writeDeadline = writeDeadline
  }

  /// Connects a session: constructs it, completes the handshake once, and returns it ready for reads
  /// and writes. The handshake runs exactly once — here, at construction — so operations never
  /// re-check it. A failed handshake throws and yields no session; the caller (which memoizes the
  /// session per target) discards it, and a later attempt reconnects.
  public static func connected(
    invoker: RemoteInvoking,
    processIdentifier: Int32,
    handshakeDeadline: TimeInterval = 30,
    readDeadline: TimeInterval = 20,
    writeDeadline: TimeInterval = 20
  ) async throws -> FBRemoteAutomationSession {
    let session = FBRemoteAutomationSession(
      invoker: invoker,
      processIdentifier: processIdentifier,
      handshakeDeadline: handshakeDeadline,
      readDeadline: readDeadline,
      writeDeadline: writeDeadline
    )
    try await session.performHandshake()
    return session
  }

  /// The capabilities the daemon advertised during the handshake (populated by `connected`).
  public var capabilities: FBRemoteAutomationCapabilities {
    capabilitiesValue
  }

  // MARK: - Handshake

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
    try await invoker.synthesizeEvent(
      record,
      implicitConfirmationInterval: implicitConfirmationInterval,
      deadline: writeDeadline + implicitConfirmationInterval
    )
  }

  /// Presses a hardware button, identified by its HID `page`/`usage` code, held for `duration`
  /// seconds, via the remote-automation channel's device-event selector.
  public func performDeviceEvent(page: UInt32, usage: UInt32, duration: TimeInterval) async throws {
    let event = try FBRemoteAutomationPayloads.deviceEvent(page: page, usage: usage, duration: duration)
    try await invoker.performDeviceEvent(event, deadline: writeDeadline + duration)
  }

  // MARK: - Reads

  /// The application's accessibility root, used as the anchor for `fetchAttributes`.
  public func applicationElement() throws -> sending Any {
    guard let element = FBRemoteAutomationPayloads.applicationElement(forProcessIdentifier: processIdentifier) else {
      throw FBRemoteInvocationError.payloadUnavailable("XCAccessibilityElement")
    }
    return element
  }

  /// The accessibility element at a screen point, expressed in points.
  public func requestElement(atX x: Double, y: Double) async throws -> sending Any? {
    let point = CGPointCreateDictionaryRepresentation(CGPoint(x: x, y: y)) as NSDictionary
    return try await invoker.requestElement(atPoint: point, deadline: readDeadline)
  }

  /// The requested attributes for an element, as returned by the daemon.
  public func fetchAttributes(_ attributes: [String], forElement element: sending Any) async throws -> sending Any? {
    return try await invoker.fetchAttributes(attributes as NSArray, forElement: element, deadline: readDeadline)
  }

  /// Reads the whole element tree of the frontmost application as nested attribute dictionaries,
  /// discovering the app's pid by hit-testing `(x, y)`.
  ///
  /// Prefer `applicationElementTree(forPid:…)` when the pid is already known (e.g. from the AX
  /// frontmost query): a hit-test reads whatever process owns the centre pixel, so a system modal,
  /// launch-transition chrome, or an empty point is read instead of the target app.
  public func applicationElementTree(anchorX x: Double, y: Double, attributes: [String], childrenAttribute: String, maxDepth: Int, maxNodes: Int) async throws -> sending FBRemoteAutomationElementTree {
    let point = CGPointCreateDictionaryRepresentation(CGPoint(x: x, y: y)) as NSDictionary
    guard let anchor = try await invoker.requestElement(atPoint: point, deadline: readDeadline) else {
      return FBRemoteAutomationElementTree(root: nil, processIdentifier: 0, truncated: false)
    }
    let pid = unsafeBitCast(anchor as AnyObject, to: XCAccessibilityElementMessaging.self).processIdentifier
    return try await applicationElementTree(forPid: pid, attributes: attributes, childrenAttribute: childrenAttribute, maxDepth: maxDepth, maxNodes: maxNodes)
  }

  /// Reads the whole element tree of the application with the given pid, anchoring the root by pid
  /// via `elementWithProcessIdentifier:` — no hit-test. Recurses `fetchAttributes`, replacing each
  /// node's child element handles with the children's own attribute dictionaries. The recursion stays
  /// inside the actor because the element handles are not Sendable; only the value tree crosses out.
  public func applicationElementTree(forPid pid: pid_t, attributes: [String], childrenAttribute: String, maxDepth: Int, maxNodes: Int) async throws -> sending FBRemoteAutomationElementTree {
    guard pid > 0, let root = FBRemoteAutomationPayloads.applicationElement(forProcessIdentifier: pid) else {
      return FBRemoteAutomationElementTree(root: nil, processIdentifier: 0, truncated: false)
    }
    let tree = try await fetchAttributeTree(from: root, attributes: attributes, childrenAttribute: childrenAttribute, depth: 0, maxDepth: maxDepth, budget: maxNodes)
    return FBRemoteAutomationElementTree(root: tree.node, processIdentifier: pid, truncated: tree.truncated)
  }

  /// Recursively fetches an element and its descendants into a nested attribute-dictionary tree,
  /// bounded by `maxDepth` and the `budget` node cap (threaded through the walk and returned so
  /// siblings share one budget). Each node's child handles are replaced by the children's own
  /// dictionaries. Internal so the walk can be unit-tested with a fake invoker.
  func fetchAttributeTree(from element: sending Any, attributes: [String], childrenAttribute: String, depth: Int, maxDepth: Int, budget: Int) async throws -> sending (node: [String: Any], remaining: Int, truncated: Bool) {
    var remaining = budget - 1
    let raw = try await invoker.fetchAttributes(attributes as NSArray, forElement: element, deadline: readDeadline)
    var node = (raw as? [String: Any]) ?? [:]
    var childNodes: [[String: Any]] = []
    var truncated = false
    if var childHandles = node[childrenAttribute] as? [Any] {
      node[childrenAttribute] = nil
      if depth < maxDepth {
        while !childHandles.isEmpty, remaining > 0 {
          // The walk is sequential within the actor and each handle is consumed exactly once, so
          // transferring it into the recursive read is race-free; region isolation can't prove that
          // because the handle shares a region with the array it came from.
          nonisolated(unsafe) let childHandle = childHandles.removeFirst()
          let result = try await fetchAttributeTree(from: childHandle, attributes: attributes, childrenAttribute: childrenAttribute, depth: depth + 1, maxDepth: maxDepth, budget: remaining)
          childNodes.append(result.node)
          remaining = result.remaining
          truncated = truncated || result.truncated
        }
        // Children left unvisited mean the shared node budget ran out before the walk finished them.
        if !childHandles.isEmpty { truncated = true }
      } else if !childHandles.isEmpty {
        // The depth bound stops the walk from descending into this node's existing children.
        truncated = true
      }
    }
    node[childrenAttribute] = childNodes
    return (node, remaining, truncated)
  }

  /// Sets `value` on the element at a screen point via the remote-automation channel. The element
  /// handle stays a disconnected local (received from the session and used once).
  public func setValue(_ value: String, atX x: Double, y: Double, valueAttribute: String) async throws {
    let point = CGPointCreateDictionaryRepresentation(CGPoint(x: x, y: y)) as NSDictionary
    guard let element = try await invoker.requestElement(atPoint: point, deadline: readDeadline) else {
      throw FBRemoteInvocationError.payloadUnavailable("element at (\(x), \(y))")
    }
    try await invoker.setAttribute(valueAttribute as NSString, value: value as NSString, forElement: element, deadline: writeDeadline)
  }
}

/// The result of a whole-tree read: the frontmost app's root as nested attribute dictionaries, the
/// app's process identifier (discovered by hit-test), and whether the walk was cut short by the
/// depth or node-count bound — so a caller can distinguish a bounded tree from a complete one and
/// tag its elements with the real owning pid rather than a placeholder.
public struct FBRemoteAutomationElementTree {
  public let root: Any?
  public let processIdentifier: pid_t
  public let truncated: Bool

  public init(root: Any?, processIdentifier: pid_t, truncated: Bool) {
    self.root = root
    self.processIdentifier = processIdentifier
    self.truncated = truncated
  }
}

/// Reads the process identifier off an `XCAccessibilityElement` returned by the daemon. The class is
/// runtime-loaded (not linked), so it is messaged through this module-local `@objc` protocol.
@objc private protocol XCAccessibilityElementMessaging {
  var processIdentifier: CInt { get }
}

/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import FBControlCore
import Foundation

/// The `FBUIAutomation` backend that reads via the `SimulatorFrameworkBridge` guest `accessibility`
/// service — an in-simulator accessibility client, with no automation daemon, DTX channel, or test
/// bundle. XCUI-grade like `.remoteAutomation`, but light like `.accessibility`.
///
/// One-shot per read: each verb resolves the target pid (frontmost via the CoreSimulator AX path, or a
/// given application pid), spawns the guest with `accessibility describe --pid <pid>`, parses its JSON
/// tree, and feeds it through the **same** serializer path the `testmanagerd` backend uses
/// (`FBRemoteAutomationPlatformElement` -> `FBSimulatorAccessibilitySerializer`), because the guest
/// emits the identical `XC_kAXXC*` node shape. The output schema is therefore byte-identical across
/// the two backends and needs no new serialization code.
///
/// Reads only for now. Element writes (tap/scroll/set-value, via in-guest HID synthesis) land in a
/// later change; until then those verbs throw `FBAXBridgeError.operationUnsupported`. The spawn goes
/// through a small internal seam so a persistent-socket transport can replace it later without
/// touching this verb logic.
///
// SAFETY: immutable after init — it holds the target and a transport; the persistent transport is an
// actor and the one-shot transport is a stateless value, and the verb logic keeps no mutable state.
// `Sendable` lets a long-lived caller (e.g. `ui shell`) hold one warm reader across reads.
// patternlint-disable-next-line unchecked-sendable
final class FBAXBridgeUIAutomation: FBAXTreeReader, @unchecked Sendable {

  private let simulator: FBSimulator
  private let transport: any FBAXBridgeTransport

  init(simulator: FBSimulator, transport: any FBAXBridgeTransport) {
    self.simulator = simulator
    self.transport = transport
  }

  // MARK: - Reads

  func describe(
    _ query: FBAccessibilityElementQuery,
    options: FBAccessibilityRequestOptions
  ) async throws -> FBAccessibilityElementsResponse {
    try await describeTree(query, options: options)
  }

  nonisolated var backend: FBUIAutomationBackend { .axBridge }

  /// Re-raises the transport-level `FBAXBridgeError.applicationUnavailable` as the backend-neutral
  /// `FBUIAutomationError.applicationUnavailable`, so a caller holding `any FBUIAutomation` sees the
  /// same typed error for a dead pid regardless of which backend served the read (the remote backend
  /// throws the neutral case directly). Other bridge errors pass through untouched.
  private func translatingSeamErrors<T>(_ body: () async throws -> T) async throws -> T {
    do {
      return try await body()
    } catch let FBAXBridgeError.applicationUnavailable(pid) {
      throw FBUIAutomationError.applicationUnavailable(backend: backend, pid: pid)
    }
  }

  /// Reads and flattens the tree a query targets, through the configured transport. `.application`
  /// reads the named pid; every other query is a frontmost read served by a single fused guest query
  /// (resolve frontmost + read tree in one IPC hop), which reports the pid it resolved.
  func readElements(
    for query: FBAccessibilityElementQuery,
    keys: Set<FBAXKeys>,
    nestedFormat: Bool,
    filter: FBAccessibilityElementFilter
  ) async throws -> [FBJSONValue] {
    try await translatingSeamErrors {
      let read: (tree: [String: Any], truncated: Bool, pid: pid_t)
      if case let .application(pid) = query {
        let application = try await readTree(forPid: pid)
        read = (application.tree, application.truncated, pid)
      } else {
        read = try await readFrontmostTree()
      }
      warnIfTruncated(read.truncated)
      return FBAXTreeSerialization.describeAllElements(
        fromTree: read.tree, keys: keys, nestedFormat: nestedFormat, pid: read.pid, filter: filter
      )
    }
  }

  func hitTest(
    at point: CGPoint,
    options: FBAccessibilityRequestOptions
  ) async throws -> FBAccessibilityElementsResponse? {
    try await translatingSeamErrors {
      // A single system-wide guest hit-test resolves the element at the point and its owning app
      // in-guest — no host-side CoreSimulator frontmost query, one IPC hop. `.point` is positional, so
      // a system-wide hit-test is exactly its semantics (unlike a whole-tree read of "frontmost").
      let response = try await transport.hitTest(x: Double(point.x), y: Double(point.y))
      guard let hit = try FBAXBridgeResponse.systemWideHitTest(fromResponse: response) else {
        return nil
      }
      let element = FBAXTreeSerialization.buildPlatformElementTree(from: hit.node, pid: hit.pid)
      let formatted = FBSimulatorAccessibilitySerializer.formattedDescription(
        ofElement: element, token: "", nestedFormat: false, keys: options.keys, collector: nil, coverageGrid: nil
      )
      return FBAccessibilityElementsResponse(elements: formatted)
    }
  }

  func wait(
    _ query: FBAccessibilityElementQuery,
    timeout: TimeInterval,
    pollInterval: TimeInterval
  ) async throws {
    try await FBUIAutomationPolling.waitForMarker(
      query, backend: .axBridge, timeout: timeout, pollInterval: pollInterval
    ) { markerValue, key, _ in
      // Re-read the frontmost tree each poll (one fused guest query) so an app that launches mid-wait is
      // picked up — no separate pid resolution.
      do {
        // A poll reads the tree directly (not through `readElements`), so the truncation warning is
        // not logged on every poll iteration — matching the describe-path-only warning above.
        let read = try await self.readFrontmostTree()
        let elements = FBAXTreeSerialization.describeAllElements(
          fromTree: read.tree, keys: FBAXKeys.defaultSet.union([key.serializationKey]), nestedFormat: false, pid: read.pid
        )
        return FBAXTreeSerialization.matchingElement(inElements: elements, markerValue: markerValue, key: key) != nil ? true : nil
      } catch let error as FBAXBridgeError {
        // A frontmost that isn't up yet, a tree that isn't readable yet, or a pid that names no
        // readable app (an app still launching) is "not there yet" — keep polling. A missing guest
        // binary won't resolve by waiting, so surface it (and any unexpected non-bridge error) at once
        // rather than burning the whole timeout.
        switch error {
        case .frontmostUnavailable, .guestFailure, .applicationUnavailable:
          return nil
        case .bridgeUnavailable:
          throw error
        }
      }
    }
  }

  // MARK: - Writes (added in a later change)

  func tap(
    _ query: FBAccessibilityElementQuery,
    expectedValue: String?,
    expectedKey: FBAXSearchableKey
  ) async throws {
    throw FBUIAutomationError.operationUnsupported(backend: .axBridge, operation: "A tap")
  }

  func setValue(_ value: String, for query: FBAccessibilityElementQuery) async throws {
    throw FBUIAutomationError.operationUnsupported(backend: .axBridge, operation: "Setting a value")
  }

  func scroll(_ query: FBAccessibilityElementQuery, direction: FBAccessibilityScrollDirection) async throws {
    throw FBUIAutomationError.operationUnsupported(backend: .axBridge, operation: "Scroll")
  }

  func frame(_ query: FBAccessibilityElementQuery) async throws -> CGRect {
    throw FBUIAutomationError.operationUnsupported(backend: .axBridge, operation: "Reading an element frame")
  }

  // MARK: - Transport seam (one-shot spawn)

  /// Reads the full attribute tree for `pid` through the configured transport (one-shot spawn or
  /// persistent socket), plus whether the guest's walk was cut short by the depth or node bound. The
  /// verb logic above is transport-agnostic; only the injected `transport` differs. `.point` does not
  /// use this — it uses the targeted `transport.hitTest`.
  private func readTree(forPid pid: pid_t) async throws -> (tree: [String: Any], truncated: Bool) {
    let response = try await transport.read(
      pid: pid, maxDepth: FBAXTreeSerialization.maxReadDepth, maxNodes: FBAXTreeSerialization.maxReadNodes
    )
    return try FBAXBridgeResponse.tree(fromResponse: response, pid: pid)
  }

  /// Reads the frontmost app's tree in a **single fused guest query**: the guest resolves the frontmost
  /// app in-guest (system-wide hit-test at the screen-centre anchor) and reads its tree in one IPC hop,
  /// returning the tree, the truncation flag, and the pid it resolved. This is the axbridge frontmost
  /// optimization — no host-side CoreSimulator query and no separate pid round-trip.
  private func readFrontmostTree() async throws -> (tree: [String: Any], truncated: Bool, pid: pid_t) {
    let anchor = frontmostAnchor()
    let response = try await transport.readFrontmost(
      x: anchor.x, y: anchor.y, maxDepth: FBAXTreeSerialization.maxReadDepth, maxNodes: FBAXTreeSerialization.maxReadNodes
    )
    return try FBAXBridgeResponse.frontmostTree(fromResponse: response)
  }

  /// The screen-centre anchor (in points) for the in-guest frontmost hit-test. The same point the
  /// remote backend uses (`FBSimulatorRemoteAutomation.anchorPoint`), so the two agree on "frontmost".
  private func frontmostAnchor() -> (x: Double, y: Double) {
    let info = simulator.screenInfo
    return FBSimulatorRemoteAutomation.anchorPoint(
      widthPixels: info?.widthPixels ?? 828, heightPixels: info?.heightPixels ?? 1792, scale: info?.scale ?? 2
    )
  }

  /// Warns when a whole-tree read hit the depth or node bound, so a truncated tree is never passed off
  /// as complete. The `wait` poll deliberately does not call this — it would log on every iteration.
  private func warnIfTruncated(_ truncated: Bool) {
    guard truncated else { return }
    _ = simulator.logger?.log("axbridge read hit the bound (maxDepth \(FBAXTreeSerialization.maxReadDepth), maxNodes \(FBAXTreeSerialization.maxReadNodes)); the returned tree is truncated and incomplete.")
  }
}

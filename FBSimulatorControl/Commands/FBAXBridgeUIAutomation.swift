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

  /// The transport lifecycle this reader was vended for. Held only so `backend` reports the case the
  /// caller selected; the injected transport already encodes the behavioural difference.
  private let persistence: FBAXBridgePersistence

  /// How frontmost reads resolve the foreground app. Defaults to the positional `.centerPoint`; a caller
  /// (e.g. sime2e) can select `.windowServer` or `.runningBoard`.
  private let frontmostMethod: FBAXBridgeFrontmostMethod

  init(simulator: FBSimulator, transport: any FBAXBridgeTransport, persistence: FBAXBridgePersistence, frontmostMethod: FBAXBridgeFrontmostMethod = .centerPoint) {
    self.simulator = simulator
    self.transport = transport
    self.persistence = persistence
    self.frontmostMethod = frontmostMethod
  }

  // MARK: - Reads

  func describe(
    _ query: FBAccessibilityElementQuery,
    options: FBAccessibilityRequestOptions
  ) async throws -> FBAccessibilityElementsResponse {
    try await describeTree(query, options: options)
  }

  nonisolated var backend: FBUIAutomationBackend { .axBridge(persistence: persistence, frontmostMethod: frontmostMethod) }

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

  /// Reads the whole bounded attribute tree a query targets, through the configured transport (one-shot
  /// spawn or persistent socket). `.application` reads the named pid; every other query is a frontmost
  /// read served by a single fused guest query — the guest resolves the frontmost app (system-wide
  /// hit-test at the screen-centre anchor) and reads its tree in one IPC hop, reporting the pid it
  /// resolved. No host-side CoreSimulator query and no separate pid round-trip. `.point` does not use
  /// this — it uses the targeted `transport.hitTest`.
  func readRawTree(for query: FBAccessibilityElementQuery) async throws -> FBAXTreeRead {
    try await translatingSeamErrors {
      if case let .application(pid) = query {
        let response = try await transport.read(
          pid: pid, maxDepth: FBAXTreeSerialization.maxReadDepth, maxNodes: FBAXTreeSerialization.maxReadNodes
        )
        return try FBAXTreeRead(wholeTreeResponse: response, pid: pid)
      }
      let anchor = frontmostAnchor()
      let response = try await transport.readFrontmost(
        x: anchor.x, y: anchor.y, maxDepth: FBAXTreeSerialization.maxReadDepth, maxNodes: FBAXTreeSerialization.maxReadNodes, method: frontmostMethod
      )
      return try FBAXTreeRead(frontmostResponse: response)
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
      guard let hit = try FBAXTreeRead(hitTestResponse: response) else {
        return nil
      }
      let element = FBAXTreeSerialization.buildPlatformElementTree(from: hit.tree, pid: hit.pid)
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
      query, backend: backend, timeout: timeout, pollInterval: pollInterval
    ) { markerValue, key, _ in
      // Re-read the frontmost tree each poll (one fused guest query) so an app that launches mid-wait is
      // picked up — no separate pid resolution.
      do {
        // A poll reads the raw tree directly (not through `describeTree`), so `warnIfTruncated` is not
        // called on every poll iteration — matching the describe-path-only warning.
        let read = try await self.readRawTree(for: .frontmost)
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
    throw FBUIAutomationError.operationUnsupported(backend: backend, operation: "A tap")
  }

  func setValue(_ value: String, for query: FBAccessibilityElementQuery) async throws {
    throw FBUIAutomationError.operationUnsupported(backend: backend, operation: "Setting a value")
  }

  func scroll(_ query: FBAccessibilityElementQuery, direction: FBAccessibilityScrollDirection) async throws {
    throw FBUIAutomationError.operationUnsupported(backend: backend, operation: "Scroll")
  }

  func frame(_ query: FBAccessibilityElementQuery) async throws -> CGRect {
    throw FBUIAutomationError.operationUnsupported(backend: backend, operation: "Reading an element frame")
  }

  // MARK: - Frontmost anchor

  /// The screen-centre anchor (in points) for the in-guest frontmost hit-test. The same point the
  /// remote backend uses (`FBSimulatorRemoteAutomation.anchorPoint`), so the two agree on "frontmost".
  private func frontmostAnchor() -> (x: Double, y: Double) {
    let info = simulator.screenInfo
    return FBSimulatorRemoteAutomation.anchorPoint(
      widthPixels: info?.widthPixels ?? 828, heightPixels: info?.heightPixels ?? 1792, scale: info?.scale ?? 2
    )
  }

  /// Warns when a whole-tree read hit the depth or node bound, so a truncated tree is never passed off
  /// as complete. Called once per describe by the shared `describeTree`; the `wait` poll reads via
  /// `readRawTree` without describing, so it never warns per iteration. A synchronous witness satisfies
  /// the `async` protocol requirement.
  func warnIfTruncated(_ truncated: Bool) {
    guard truncated else { return }
    _ = simulator.logger?.log("axbridge read hit the bound (maxDepth \(FBAXTreeSerialization.maxReadDepth), maxNodes \(FBAXTreeSerialization.maxReadNodes)); the returned tree is truncated and incomplete.")
  }
}

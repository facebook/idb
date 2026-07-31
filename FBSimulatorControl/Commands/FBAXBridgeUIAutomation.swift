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
final class FBAXBridgeUIAutomation: FBUIAutomation {

  private let simulator: FBSimulator
  private let transport: any FBAXBridgeTransport

  private static let describeMaxDepth = 50

  init(simulator: FBSimulator, transport: any FBAXBridgeTransport) {
    self.simulator = simulator
    self.transport = transport
  }

  // MARK: - Reads

  func describe(
    _ query: FBAccessibilityElementQuery,
    options: FBAccessibilityRequestOptions
  ) async throws -> FBAccessibilityElementsResponse {
    let keys = options.keys ?? FBAXKeys.defaultSet
    let pid = try await resolvePid(for: query)
    let tree = try await readTree(forPid: pid)

    switch query {
    case .frontmost, .application:
      let elements = FBSimulatorRemoteAutomation.describeAllElements(
        fromTree: tree, keys: keys, nestedFormat: options.nestedFormat, pid: pid, filter: options.filter
      )
      return FBAccessibilityElementsResponse(
        elements: .array(elements), profilingData: nil, frameCoverage: nil, additionalFrameCoverage: nil
      )
    case let .marker(value, key, _):
      let elements = FBSimulatorRemoteAutomation.describeAllElements(
        fromTree: tree, keys: keys, nestedFormat: false, pid: pid
      )
      guard let match = FBSimulatorRemoteAutomation.matchingElement(inElements: elements, markerValue: value, key: key) else {
        throw FBAXBridgeError.elementNotFound(key: key.rawValue, value: value)
      }
      return FBAccessibilityElementsResponse(
        elements: match, profilingData: nil, frameCoverage: nil, additionalFrameCoverage: nil
      )
    case let .point(point):
      let root = FBSimulatorRemoteAutomation.buildPlatformElementTree(from: tree, pid: pid)
      guard let hit = Self.elementAtPoint(point, in: root) else {
        throw FBAXBridgeError.noElementAtPoint(x: Double(point.x), y: Double(point.y))
      }
      let element = FBSimulatorAccessibilitySerializer.formattedDescription(
        ofElement: hit, token: "", nestedFormat: false, keys: keys, collector: nil, coverageGrid: nil
      )
      return FBAccessibilityElementsResponse(
        elements: element, profilingData: nil, frameCoverage: nil, additionalFrameCoverage: nil
      )
    }
  }

  func wait(
    _ query: FBAccessibilityElementQuery,
    timeout: TimeInterval,
    pollInterval: TimeInterval
  ) async throws {
    guard case let .marker(markerValue, key, _) = query else {
      throw FBAXBridgeError.markerRequired(operation: "Waiting")
    }
    let found = try await FBUIAutomationPolling.pollUntilFound(
      timeout: timeout,
      pollInterval: pollInterval,
      clock: { Date().timeIntervalSinceReferenceDate },
      sleep: { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }
    ) { () -> Bool? in
      // Re-resolve the pid and re-read each poll so an app that launches mid-wait is picked up; any
      // failure (app not up, empty tree) is treated as "not there yet" and keeps polling.
      guard let pid = try? await self.resolvePid(for: .frontmost),
        let tree = try? await self.readTree(forPid: pid)
      else {
        return nil
      }
      let elements = FBSimulatorRemoteAutomation.describeAllElements(
        fromTree: tree, keys: FBAXKeys.defaultSet, nestedFormat: false, pid: pid
      )
      return FBSimulatorRemoteAutomation.matchingElement(inElements: elements, markerValue: markerValue, key: key) != nil ? true : nil
    }
    if found == nil {
      throw FBAXBridgeError.timedOut(key: key.rawValue, value: markerValue, timeout: timeout)
    }
  }

  // MARK: - Writes (added in a later change)

  func tap(
    _ query: FBAccessibilityElementQuery,
    expectedValue: String?,
    expectedKey: FBAXSearchableKey
  ) async throws {
    throw FBAXBridgeError.operationUnsupported(operation: "A tap")
  }

  func setValue(_ value: String, for query: FBAccessibilityElementQuery) async throws {
    throw FBAXBridgeError.operationUnsupported(operation: "Setting a value")
  }

  func scroll(_ query: FBAccessibilityElementQuery, direction: FBAccessibilityScrollDirection) async throws {
    throw FBAXBridgeError.operationUnsupported(operation: "Scroll")
  }

  func frame(_ query: FBAccessibilityElementQuery) async throws -> CGRect {
    throw FBAXBridgeError.operationUnsupported(operation: "Reading an element frame")
  }

  // MARK: - Transport seam (one-shot spawn)

  /// Resolves the pid the read targets: `.application` names it directly; every other query anchors on
  /// the frontmost app, resolved via the CoreSimulator AX window-server query (the same path the remote
  /// backend uses) rather than a screen hit-test.
  private func resolvePid(for query: FBAccessibilityElementQuery) async throws -> pid_t {
    if case let .application(pid) = query {
      return pid
    }
    let element = try await simulator.resolveElement(for: .frontmost)
    defer { element.close() }
    let pid = element.processIdentifier
    guard pid > 0 else {
      throw FBAXBridgeError.frontmostUnavailable
    }
    return pid
  }

  /// Reads the attribute tree for `pid` through the configured transport (one-shot spawn or persistent
  /// socket). The verb logic above is transport-agnostic; only the injected `transport` differs.
  private func readTree(forPid pid: pid_t) async throws -> [String: Any] {
    let response = try await transport.read(pid: pid, maxDepth: Self.describeMaxDepth)
    return try FBAXBridgeResponse.tree(fromResponse: response, pid: pid)
  }

  // MARK: - Point hit-testing

  /// The element at `point`, preferring meaningful identity over raw geometry. The full tree includes
  /// unlabeled container nodes, so the geometrically smallest node at a point is often an anonymous
  /// sub-view; a caller (e.g. a streaming hit-test server) wants the identified element it "hit". So
  /// this returns the smallest-area element containing the point that has an **identifier**, else the
  /// smallest with a **label**, else the smallest node of any kind (never nothing when the point is
  /// covered). Walks the platform-element tree the shared serializer builds, so frames match the output.
  private static func elementAtPoint(_ point: CGPoint, in root: FBAXPlatformElement) -> FBAXPlatformElement? {
    var byIdentifier: (element: FBAXPlatformElement, area: Double)?
    var byLabel: (element: FBAXPlatformElement, area: Double)?
    var byAny: (element: FBAXPlatformElement, area: Double)?
    func take(_ element: FBAXPlatformElement, area: Double, into slot: inout (element: FBAXPlatformElement, area: Double)?) {
      if let current = slot, area > current.area {
        return
      }
      slot = (element, area)
    }
    func visit(_ element: FBAXPlatformElement) {
      let frame = element.axFrame()
      if frame.contains(point) {
        let area = Double(frame.width * frame.height)
        take(element, area: area, into: &byAny)
        if element.axLabel()?.isEmpty == false {
          take(element, area: area, into: &byLabel)
        }
        if element.axIdentifier()?.isEmpty == false {
          take(element, area: area, into: &byIdentifier)
        }
      }
      for child in element.axChildren() {
        visit(child)
      }
    }
    visit(root)
    return (byIdentifier ?? byLabel ?? byAny)?.element
  }
}

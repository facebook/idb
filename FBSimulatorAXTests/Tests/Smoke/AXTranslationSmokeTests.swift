/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorAX
@testable import FBSimulatorControl
import XCTest

/// Reads a real accessibility tree out of the provided simulator through the accessibility-translation
/// backend: the host's `AXPTranslator`, answered by CoreSimulatorBridge inside the simulator. The
/// doubles-backed suites cover serialization; nothing else walks a live tree on this backend.
///
/// Reads the frontmost application, the path `describe-all` takes: the translator resolves it through
/// CoreSimulatorBridge itself, so unlike the axbridge suite this needs no window server.
final class AXTranslationSmokeTests: ProvidedSimulatorTestCase {

  private static let bundleID = "com.apple.Preferences"

  private func launchApplication() async throws {
    let simulator = self.simulator!
    let configuration = ApplicationLaunchConfiguration(
      bundleID: Self.bundleID,
      bundleName: nil,
      arguments: [],
      environment: [:],
      waitForDebugger: false,
      launchMode: .foregroundIfRunning)
    _ = try await simulator.application.launch(configuration)
    addTeardownBlock {
      // Leased-resource discipline: this suite may not own the simulator, so it leaves behind only
      // what it found.
      try? await simulator.application.kill(bundleID: Self.bundleID)
    }
  }

  /// Retries a read with no application object or nothing beneath its root, while the freshly launched
  /// application's accessibility server starts. Any other failure throws on the first attempt.
  private func describeFrontmost(retries: Int = 4) async throws -> AccessibilityElementsResponse {
    let automation = try simulator.uiAutomation(backend: .accessibility)
    let options = AccessibilityRequestOptions()
    for attempt in 0...retries {
      do {
        let response = try await automation.describe(.frontmost, options: options)
        if response.elements.elements.count > 1 || attempt == retries {
          return response
        }
      } catch AccessibilityError.noTranslationObject where attempt < retries {}
      try await Task.sleep(nanoseconds: 2 * NSEC_PER_SEC)
    }
    preconditionFailure("The retry loop returns or throws")
  }

  func testTranslatorReadsElementTree() async throws {
    try await launchApplication()
    let response = try await describeFrontmost()

    let elements = response.elements.elements
    XCTAssertGreaterThan(elements.count, 1, "The application should serialize more than its root")
    XCTAssertEqual(response.backend, .ax)

    let types = elements.compactMap { $0.type ?? nil }
    XCTAssertTrue(
      types.contains("Application"),
      "Expected an application element in the tree, got types: \(Set(types).sorted().prefix(10))")

    let screen = try XCTUnwrap(response.screen, "A tree read should report the screen it was taken against")
    XCTAssertGreaterThan(screen.width, 0)
    XCTAssertGreaterThan(screen.height, 0)
    let frames = elements.compactMap { $0.frame ?? nil }
    XCTAssertTrue(
      frames.contains { ($0.width ?? 0) > 0 && ($0.height ?? 0) > 0 },
      "At least one element should cover a non-empty area")
  }

  /// The batched read must report exactly what the per-attribute accessors it replaces report, for every key
  /// the backend answers, on both the flattened and the automation tree, in fewer round trips. How many
  /// round trips either takes depends on the runtime and the application, so only the difference is asserted.
  func testBatchedReadMatchesPerAttributeReadInFewerRoundTrips() async throws {
    try await launchApplication()
    _ = try await describeFrontmost()

    let automation = try simulator.uiAutomation(backend: .accessibility)
    for clientType in [AXClientType.noClient, .xctest] {
      var roundTrips: [AXTranslatorReads: Int64] = [:]
      func read(_ reads: AXTranslatorReads) async throws -> [AccessibilityDocumentElement] {
        let options = AccessibilityRequestOptions(
          keys: Self.comparedKeys, enableProfiling: true, translatorReads: reads, clientType: clientType)
        let response = try await automation.describe(.frontmost, options: options)
        roundTrips[reads] = try XCTUnwrap(response.profilingData?.translatorProfile?.xpcCallCount)
        return response.elements.elements
      }
      try await assertSettledReadsAgree(
        expected: { try await read(.perAttribute) }, actual: { try await read(.batched) }, "client \(clientType)")
      XCTAssertLessThan(try XCTUnwrap(roundTrips[.batched]), try XCTUnwrap(roundTrips[.perAttribute]), "client \(clientType)")
    }
  }

  /// Talking to CoreSimulatorBridge's accessibility service directly must read exactly what CoreSimulator's
  /// own client reads.
  func testTheBridgeTransportReadsWhatCoreSimulatorsClientReads() async throws {
    try await launchApplication()
    _ = try await describeFrontmost()

    let bridge = CoreSimulatorBridgeAXTranslationTransport(connector: .simulator(simulator))
    try bridge.connect()
    let viaBridge = SimulatorAccessibilityCommands(simulator: simulator, transport: bridge)
    let viaCoreSimulator = SimulatorAccessibilityCommands(
      simulator: simulator, transport: CoreSimulatorAXTranslationTransport(device: simulator.device))
    for clientType in [AXClientType.noClient, .xctest] {
      func read(_ commands: SimulatorAccessibilityCommands) async throws -> [AccessibilityDocumentElement] {
        let element = try await commands.resolveElement(for: .frontmost, clientType: clientType)
        defer { element.close() }
        return try await element.serialize(with: AccessibilityRequestOptions(keys: Self.comparedKeys)).elements.elements
      }
      try await assertSettledReadsAgree(
        expected: { try await read(viaCoreSimulator) }, actual: { try await read(viaBridge) }, "client \(clientType)")
    }
  }

  private static let comparedKeys = AXKeys.defaultSet.union([.expanded, .placeholder, .hidden, .focused])

  /// Asserts `actual` reports what `expected` does. The application may still be settling, so the comparison
  /// is made only across a window in which two `expected` reads agree: the `actual` read between them then
  /// saw the same tree. Element by element, so a mismatch names the element rather than printing two trees.
  private func assertSettledReadsAgree(
    expected: () async throws -> [AccessibilityDocumentElement],
    actual: () async throws -> [AccessibilityDocumentElement],
    _ context: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async throws {
    var settled: (actual: [AccessibilityDocumentElement], expected: [AccessibilityDocumentElement])?
    for _ in 0..<5 {
      let before = try await expected().map(Self.withSortedTraits)
      let candidate = try await actual().map(Self.withSortedTraits)
      let after = try await expected().map(Self.withSortedTraits)
      if before == after {
        settled = (candidate, after)
        break
      }
      try await Task.sleep(nanoseconds: NSEC_PER_SEC)
    }
    let (actualElements, expectedElements) = try XCTUnwrap(
      settled, "\(context): the tree never held still between two reads", file: file, line: line)
    XCTAssertGreaterThan(expectedElements.count, 1, context, file: file, line: line)
    XCTAssertEqual(actualElements.count, expectedElements.count, context, file: file, line: line)
    for (index, (actualElement, expectedElement)) in zip(actualElements, expectedElements).enumerated() {
      XCTAssertEqual(actualElement, expectedElement, "\(context), element \(index)", file: file, line: line)
    }
  }

  /// Traits are decoded from a bitmask into a set, so their order is not part of what either read reports.
  private static func withSortedTraits(_ element: AccessibilityDocumentElement) -> AccessibilityDocumentElement {
    var element = element
    element.traits = element.traits.map { $0?.sorted() }
    return element
  }
}

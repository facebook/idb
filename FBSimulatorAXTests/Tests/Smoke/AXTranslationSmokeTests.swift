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
      var options = AccessibilityRequestOptions(
        keys: AXKeys.defaultSet.union([.expanded, .placeholder, .hidden, .focused]), enableProfiling: true,
        clientType: clientType)
      func read(_ reads: AXTranslatorReads) async throws -> (elements: [AccessibilityDocumentElement], roundTrips: Int64) {
        options.translatorReads = reads
        let response = try await automation.describe(.frontmost, options: options)
        let roundTrips = try XCTUnwrap(response.profilingData?.translatorProfile?.xpcCallCount)
        return (response.elements.elements.map(Self.withSortedTraits), roundTrips)
      }
      // The application may still be settling, so the comparison is made only across a window in which two
      // per-attribute reads agree: the batched read between them then saw the same tree.
      var settled: (batched: (elements: [AccessibilityDocumentElement], roundTrips: Int64), perAttribute: (elements: [AccessibilityDocumentElement], roundTrips: Int64))?
      for _ in 0..<5 {
        let before = try await read(.perAttribute)
        let batched = try await read(.batched)
        let after = try await read(.perAttribute)
        if before.elements == after.elements {
          settled = (batched, after)
          break
        }
        try await Task.sleep(nanoseconds: NSEC_PER_SEC)
      }
      let (batched, perAttribute) = try XCTUnwrap(settled, "client \(clientType): the tree never held still between two reads")
      XCTAssertLessThan(batched.roundTrips, perAttribute.roundTrips, "client \(clientType)")
      let (actual, expected) = (batched.elements, perAttribute.elements)
      XCTAssertGreaterThan(expected.count, 1, "client \(clientType)")
      XCTAssertEqual(actual.count, expected.count, "client \(clientType)")
      // Element by element, so a mismatch names the element rather than printing two whole trees.
      for (index, (actualElement, expectedElement)) in zip(actual, expected).enumerated() {
        XCTAssertEqual(actualElement, expectedElement, "client \(clientType), element \(index)")
      }
    }
  }

  /// Traits are decoded from a bitmask into a set, so their order is not part of what either read reports.
  private static func withSortedTraits(_ element: AccessibilityDocumentElement) -> AccessibilityDocumentElement {
    var element = element
    element.traits = element.traits.map { $0?.sorted() }
    return element
  }
}

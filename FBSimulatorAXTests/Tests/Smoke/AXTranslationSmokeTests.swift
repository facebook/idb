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
}

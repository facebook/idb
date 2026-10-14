/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import FBSimulatorCodeInjection
import FBSimulatorControl
import XCTest

/// Injects code into processes on a booted simulator through the library's public API alone, as a
/// consumer outside idb would, and reads state only code running inside them can know. The payload
/// is a prebuilt fixture dylib, and nothing is installed: Settings, a system app, hosts the injected
/// code.
final class CodeInjectionSmokeTests: ProvidedSimulatorTestCase {

  private static let bundleID = "com.apple.Preferences"
  /// Settings opens on a long list, so its windows hold far more views than this once it is drawn.
  private static let drawnViewCount = 20
  private static let drawTimeout: TimeInterval = 30

  private var payloadPath: String!

  override func setUp() async throws {
    try await super.setUp()
    payloadPath = try XCTUnwrap(BundledResources.path(forItem: "libCodeInjectionPayload-iOS.dylib"), "The payload is a resource of this bundle")
    let simulator = self.simulator!
    addTeardownBlock {
      try? await simulator.application.kill(bundleID: Self.bundleID)
    }
  }

  func testInjectedCodeRunsInTheAppOnThisSimulator() async throws {
    let session = try await simulator.codeInjection.inject(into: .application(bundleID: Self.bundleID))

    let description = try await session.execute(dylibAtPath: payloadPath, symbol: "CodeInjectionPayloadDescribeProcess")
    try await session.close()

    XCTAssertEqual(description, "\(simulator.udid) \(Self.bundleID)")
  }

  func testInjectedCodeReadsTheAppsViews() async throws {
    let session = try await simulator.codeInjection.inject(into: .application(bundleID: Self.bundleID))

    // A freshly launched app may not have drawn its first screen yet.
    let deadline = Date().addingTimeInterval(Self.drawTimeout)
    var viewCount = 0
    repeat {
      let output = try await session.execute(dylibAtPath: payloadPath, symbol: "CodeInjectionPayloadCountViews")
      viewCount = try XCTUnwrap(Int(output), output)
      if viewCount > Self.drawnViewCount {
        break
      }
      try await Task.sleep(nanoseconds: 500_000_000)
    } while Date() < deadline
    try await session.close()

    XCTAssertGreaterThan(viewCount, Self.drawnViewCount)
  }

  func testAReattachedSessionSeesStateAnEarlierOneLeft() async throws {
    let first = try await simulator.codeInjection.inject(into: .application(bundleID: Self.bundleID))
    let firstCount = try await first.execute(dylibAtPath: payloadPath, symbol: "CodeInjectionPayloadCountInjections")
    try await first.close()

    let second = try await simulator.codeInjection.inject(into: .application(bundleID: Self.bundleID, reattach: true))
    let secondCount = try await second.execute(dylibAtPath: payloadPath, symbol: "CodeInjectionPayloadCountInjections")
    try await second.close()

    XCTAssertEqual(firstCount, "1", "A relaunched app starts with no injections")
    XCTAssertEqual(secondCount, "2", "A reattached session runs in the same process as the first")
    XCTAssertEqual(second.sessionID, first.sessionID)
  }

  func testInjectedCodeRunsInTheGuestBridgeOnThisSimulator() async throws {
    let session = try await skippingIfGuestServiceSpawnUnavailable { try await simulator.codeInjection.inject(into: .simulator) }

    let description = try await session.execute(dylibAtPath: payloadPath, symbol: "CodeInjectionPayloadDescribeProcess")
    try await session.close()

    XCTAssertEqual(description, "\(simulator.udid) ", "The guest bridge is a process on this simulator, and not an app")
  }
}

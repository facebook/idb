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

private struct NoHostCommands: Error, CustomStringConvertible {
  var description: String { "the smoke tests answer no host commands" }
}

/// Injects code into processes on a booted simulator, as a consumer outside idb would, and reads
/// state only code running inside them can know. The payload is a prebuilt fixture dylib, and
/// nothing is installed: Settings, a system app, hosts the injected code.
final class CodeInjectionSmokeTests: ProvidedSimulatorTestCase {

  private static let bundleID = "com.apple.Preferences"
  private static let connectTimeout: TimeInterval = 120
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
    let client = try await connect(to: simulator.repl.startApp(bundleID: Self.bundleID, reuseSession: false))
    defer { client.close() }

    let description = try await execute("CodeInjectionPayloadDescribeProcess", with: client)

    XCTAssertEqual(description, "\(simulator.udid) \(Self.bundleID)")
  }

  func testInjectedCodeReadsTheAppsViews() async throws {
    let client = try await connect(to: simulator.repl.startApp(bundleID: Self.bundleID, reuseSession: false))
    defer { client.close() }

    // A freshly launched app may not have drawn its first screen yet.
    let deadline = Date().addingTimeInterval(Self.drawTimeout)
    var viewCount = 0
    repeat {
      let output = try await execute("CodeInjectionPayloadCountViews", with: client)
      viewCount = try XCTUnwrap(Int(output), output)
      if viewCount > Self.drawnViewCount {
        break
      }
      try await Task.sleep(nanoseconds: 500_000_000)
    } while Date() < deadline
    XCTAssertGreaterThan(viewCount, Self.drawnViewCount)
  }

  func testAReattachedSessionSeesStateAnEarlierOneLeft() async throws {
    let first = try await connect(to: simulator.repl.startApp(bundleID: Self.bundleID, reuseSession: false))
    let firstCount = try await execute("CodeInjectionPayloadCountInjections", with: first)
    first.close()

    let second = try await connect(to: simulator.repl.startApp(bundleID: Self.bundleID, reuseSession: true))
    defer { second.close() }
    let secondCount = try await execute("CodeInjectionPayloadCountInjections", with: second)

    XCTAssertEqual(firstCount, "1", "A relaunched app starts with no injections")
    XCTAssertEqual(secondCount, "2", "A reattached session runs in the same process as the first")
  }

  func testInjectedCodeRunsInTheGuestBridgeOnThisSimulator() async throws {
    let repl = try await skippingIfGuestServiceSpawnUnavailable { try await simulator.repl.startSimulator() }
    let client = try await connect(to: repl)

    let description = try await execute("CodeInjectionPayloadDescribeProcess", with: client)
    client.close()
    try await repl.waitForHostToFinish()

    XCTAssertEqual(description, "\(simulator.udid) ", "The guest bridge is a process on this simulator, and not an app")
  }

  private func connect(to repl: LaunchedRepl) async throws -> ReplControlClient {
    let client = try await ReplControlClient.connect(path: repl.socketPath, timeout: Self.connectTimeout)
    _ = try await client.readGreeting()
    return client
  }

  private func execute(_ symbol: String, with client: ReplControlClient) async throws -> String {
    let result = try await client.execute(dylibPath: payloadPath, symbol: symbol) { _ in .failure(NoHostCommands()) }
    XCTAssertTrue(result.success, result.output)
    return result.output
  }
}

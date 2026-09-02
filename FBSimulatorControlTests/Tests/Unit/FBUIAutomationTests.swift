/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import XCTest

final class FBUIAutomationTests: XCTestCase {

  func testAnchorPointIsScreenCentreInPoints() {
    let anchor = FBAXBridgeUIAutomation.anchorPoint(widthPixels: 828, heightPixels: 1792, scale: 2)
    XCTAssertEqual(anchor.x, 207, accuracy: 0.001)
    XCTAssertEqual(anchor.y, 448, accuracy: 0.001)
  }

  func testAnchorPointHonoursScale() {
    let anchor = FBAXBridgeUIAutomation.anchorPoint(widthPixels: 1206, heightPixels: 2622, scale: 3)
    XCTAssertEqual(anchor.x, 201, accuracy: 0.001)
    XCTAssertEqual(anchor.y, 437, accuracy: 0.001)
  }

  func testAnchorPointGuardsAgainstZeroScale() {
    let anchor = FBAXBridgeUIAutomation.anchorPoint(widthPixels: 400, heightPixels: 800, scale: 0)
    XCTAssertEqual(anchor.x, 200, accuracy: 0.001)
    XCTAssertEqual(anchor.y, 400, accuracy: 0.001)
  }

  // Which transport instance a reader is vended with decides whether the guest `serve` process is
  // shared across reads or spawned for each one. Constructing the axbridge backends touches no
  // device, so this needs no booted simulator.

  private static func backend(_ persistence: FBAXBridgePersistence) -> FBUIAutomationBackend {
    .axBridge(persistence: persistence, frontmostMethod: .windowServer, automationMode: true)
  }

  private func transport(
    _ simulator: FBSimulator, _ persistence: FBAXBridgePersistence
  ) throws -> FBAXBridgePersistentTransport {
    let reader = try simulator.uiAutomation(backend: Self.backend(persistence))
    let bridgeReader = try XCTUnwrap(reader as? FBAXBridgeUIAutomation)
    return try XCTUnwrap(bridgeReader.transport as? FBAXBridgePersistentTransport)
  }

  func testEverySharedBackendCallSharesOneTransport() throws {
    let simulator = FBSimulatorTestSupport.testableSimulator()
    XCTAssertTrue(try transport(simulator, .shared) === (try transport(simulator, .shared)))
  }

  func testEveryExclusiveBackendCallSharesOneTransport() throws {
    let simulator = FBSimulatorTestSupport.testableSimulator()
    XCTAssertTrue(try transport(simulator, .exclusive) === (try transport(simulator, .exclusive)))
  }

  // The two lanes reach different guests, so handing a shared read the exclusive transport would read
  // over a bridge nobody else can see, and the reverse would put the caller back to holding one others
  // want. Memoization is therefore keyed by persistence, not just by simulator.
  func testSharedAndExclusiveDoNotShareATransport() throws {
    let simulator = FBSimulatorTestSupport.testableSimulator()
    XCTAssertFalse(try transport(simulator, .shared) === (try transport(simulator, .exclusive)))
  }

  func testTransportsAreNotSharedAcrossSimulators() throws {
    let first = try transport(FBSimulatorTestSupport.testableSimulator(), .shared)
    let second = try transport(FBSimulatorTestSupport.testableSimulator(), .shared)
    XCTAssertFalse(first === second)
  }

  func testReadersDifferingOnlyInReaderOptionsShareOneTransport() throws {
    let simulator = FBSimulatorTestSupport.testableSimulator()
    let shared = try transport(simulator, .shared)
    let otherOptions = FBUIAutomationBackend.axBridge(
      persistence: .shared, frontmostMethod: .centerPoint, automationMode: nil
    )
    let reader = try XCTUnwrap(try simulator.uiAutomation(backend: otherOptions) as? FBAXBridgeUIAutomation)
    // `frontmostMethod` and `automationMode` are the reader's, not the transport's, so differing on
    // them must not cost a second guest.
    XCTAssertTrue((reader.transport as? FBAXBridgePersistentTransport) === shared)
  }

  func testEachOneShotBackendCallBuildsAOneShotTransport() throws {
    let simulator = FBSimulatorTestSupport.testableSimulator()
    let backend = FBUIAutomationBackend.axBridge(
      persistence: .oneShot, frontmostMethod: .windowServer, automationMode: true
    )
    // Both calls, because the claim is about every call: the one-shot transport is a stateless value
    // with nothing to reuse, so it must stay per-call whatever the persistent one does.
    for _ in 0..<2 {
      let reader = try XCTUnwrap(try simulator.uiAutomation(backend: backend) as? FBAXBridgeUIAutomation)
      XCTAssertTrue(reader.transport is FBAXBridgeOneshotTransport)
    }
  }
}

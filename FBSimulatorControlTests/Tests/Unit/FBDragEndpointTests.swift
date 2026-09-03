/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import FBControlCore
@testable import FBSimulatorControl
import Foundation
import XCTest

/// Coverage for what a drag will accept as an endpoint. Every backend classifies its two endpoints
/// through `FBDragEndpoint` before resolving either, so this is the one place a drag decides which
/// queries name something to press and which do not.
///
/// The dangerous direction is a query that stops being refused: `.frontmost` resolves to the middle of
/// the application's own rectangle, so accepting one would drag from somewhere the caller never named
/// and report success.
final class FBDragEndpointTests: XCTestCase {

  private static let backends: [FBUIAutomationBackend] = [
    .accessibility,
    .axBridge(persistence: .oneShot, frontmostMethod: .windowServer, automationMode: true),
  ]

  func testACoordinateIsItsOwnEndpoint() throws {
    let point = CGPoint(x: 10, y: 20)
    for backend in Self.backends {
      XCTAssertEqual(try FBDragEndpoint(.point(point), backend: backend), .point(point), "\(backend)")
    }
  }

  // The key and depth travel with the marker rather than being defaulted here: the backend that
  // resolves it searches on the caller's key, and a silently dropped key matches on the label instead.
  func testAMarkerCarriesTheKeyAndDepthItWasNamedWith() throws {
    let query = FBAccessibilityElementQuery.marker(value: "Album", key: .uniqueID, depth: 5)
    for backend in Self.backends {
      XCTAssertEqual(
        try FBDragEndpoint(query, backend: backend),
        .marker(value: "Album", key: .uniqueID, depth: 5),
        "\(backend)")
    }
  }

  func testWholeTreeQueriesAreNotEndpoints() {
    for backend in Self.backends {
      for query in [FBAccessibilityElementQuery.frontmost, .application(pid: 99)] {
        do {
          _ = try FBDragEndpoint(query, backend: backend)
          XCTFail("\(query) must not be accepted as a drag endpoint by \(backend)")
        } catch let error as FBUIAutomationError {
          guard case let .pointOrMarkerRequired(thrownBackend, operation) = error else {
            return XCTFail("expected pointOrMarkerRequired, got \(error)")
          }
          XCTAssertEqual(thrownBackend, backend, "the refusal must name the backend that refused")
          XCTAssertEqual(operation, "A drag endpoint", "the refusal must name the verb")
        } catch {
          XCTFail("expected an FBUIAutomationError, got \(error)")
        }
      }
    }
  }
}

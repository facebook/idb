/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import CoreGraphics
@preconcurrency import FBControlCore
@preconcurrency import FBSimulatorControl
import Foundation
import GRPC
import IDBGRPCSwift
import XCTest

/// Pins the `accessibility_action` request → action translation: which handler a request reaches,
/// what each endpoint resolves to, which requests are refused, and the sentence a non-simulator
/// target is refused with. A request that stops being refused is the dangerous direction -- it
/// reaches the simulator and does something the caller did not ask for.
final class AccessibilityActionRequestTranslationTests: XCTestCase {

  // MARK: - Helpers

  private func action(
    _ mutate: (inout Idb_AccessibilityActionRequest) -> Void
  ) throws -> AccessibilityActionRequestTranslation.Action {
    var request = Idb_AccessibilityActionRequest()
    mutate(&request)
    return try AccessibilityActionRequestTranslation.action(from: request)
  }

  /// A drag between two points far enough apart that the default delta is legal.
  private func drag(
    _ mutate: (inout Idb_AccessibilityActionRequest) -> Void = { _ in }
  ) throws -> AccessibilityActionRequestTranslation.Action {
    try action {
      $0.point = .with { point in
        point.x = 10
        point.y = 20
      }
      $0.drag = .with { drag in
        drag.point = .with { point in
          point.x = 200
          point.y = 20
        }
      }
      mutate(&$0)
    }
  }

  private func assertRejected(
    _ mutate: (inout Idb_AccessibilityActionRequest) -> Void,
    mentioning fragment: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertThrowsError(try drag(mutate), file: file, line: line) { error in
      guard let status = error as? GRPCStatus else {
        return XCTFail("expected a GRPCStatus, got \(error)", file: file, line: line)
      }
      XCTAssertEqual(status.code, .invalidArgument, file: file, line: line)
      let message = status.message ?? ""
      XCTAssertTrue(
        message.contains(fragment), "\"\(message)\" does not mention \(fragment)", file: file, line: line)
    }
  }

  // MARK: - Routing

  func testADragRequestBecomesADrag() throws {
    guard case let .drag(source, destination, _) = try drag() else {
      return XCTFail("a request carrying a drag must not reach another action")
    }
    XCTAssertEqual(source, .point(CGPoint(x: 10, y: 20)))
    XCTAssertEqual(destination, .point(CGPoint(x: 200, y: 20)))
  }

  func testARequestWithNoActionIsRefused() {
    XCTAssertThrowsError(try action { _ in }) { error in
      guard let status = error as? GRPCStatus else {
        return XCTFail("expected a GRPCStatus, got \(error)")
      }
      // Also what an action added after this companion was built deserializes as.
      XCTAssertEqual(status.code, .invalidArgument)
    }
  }

  // MARK: - Endpoints

  func testAMarkerEndpointCarriesItsOwnKeyAndDepth() throws {
    let action = try action {
      $0.marker = "Photo"
      $0.matchKey = .uniqueID
      $0.depth = 5
      $0.drag = .with { drag in
        drag.marker = "Album"
        drag.destinationMatchKey = .label
        drag.destinationDepth = 3
      }
    }
    guard case let .drag(source, destination, _) = action else {
      return XCTFail("expected a drag")
    }
    XCTAssertEqual(source, .marker(value: "Photo", key: .uniqueID, depth: 5))
    XCTAssertEqual(destination, .marker(value: "Album", key: .label, depth: 3))
  }

  func testAMissingSourceIsRefusedByName() {
    // Unlike a scroll, a drag has nothing sensible to do with the frontmost app.
    assertRejected({ $0.target = nil }, mentioning: "source")
  }

  func testAMissingDestinationIsRefusedByName() {
    assertRejected({ $0.drag.destination = nil }, mentioning: "destination")
  }

  func testDraggingAnElementOntoItselfIsRefused() {
    // The gesture would run and change nothing, which reads to the caller as a silent no-op.
    assertRejected(
      {
        $0.drag.point = .with { point in
          point.x = 10
          point.y = 20
        }
      }, mentioning: "same element")
  }

  // MARK: - Options

  func testUnsetOptionsAreTheDefaults() throws {
    guard case let .drag(_, _, options) = try drag() else {
      return XCTFail("expected a drag")
    }
    // Zero is unset on the wire and none of these are useful at zero, so the server's defaults
    // stand in -- a press of zero would make the gesture a flick.
    XCTAssertEqual(options, FBDragOptions())
  }

  func testEveryOptionIsCarriedThrough() throws {
    let action = try drag {
      $0.drag.pressDuration = 1
      $0.drag.duration = 2
      $0.drag.releaseDuration = 0.25
      $0.drag.delta = 5
    }
    guard case let .drag(_, _, options) = action else {
      return XCTFail("expected a drag")
    }
    XCTAssertEqual(
      options, FBDragOptions(pressDuration: 1, duration: 2, releaseDuration: 0.25, delta: 5))
  }

  func testEveryNegativeOptionIsRefusedByNameAndValue() {
    assertRejected({ $0.drag.pressDuration = -1 }, mentioning: "press_duration")
    assertRejected({ $0.drag.pressDuration = -1 }, mentioning: "-1")
    assertRejected({ $0.drag.duration = -1 }, mentioning: "duration")
    assertRejected({ $0.drag.releaseDuration = -1 }, mentioning: "release_duration")
    assertRejected({ $0.drag.delta = -1 }, mentioning: "delta")
  }

  func testADeltaAtOrAboveTheDistanceIsRefusedShowingBoth() {
    // One sample means one jump, which iOS reads as a flick rather than a drag. The two points are
    // 190 apart, so a delta of 190 samples the path exactly once.
    assertRejected({ $0.drag.delta = 190 }, mentioning: "190")
    assertRejected({ $0.drag.delta = 500 }, mentioning: "500")
  }

  func testADeltaIsNotCheckedAgainstAMarkerEndpoint() throws {
    // A marker's position is resolved by the backend, so there is no distance to compare against
    // here; the backend rejects it once it knows one.
    let action = try action {
      $0.marker = "Photo"
      $0.drag = .with { drag in
        drag.marker = "Album"
        drag.delta = 10_000
      }
    }
    guard case let .drag(_, _, options) = action else {
      return XCTFail("expected a drag")
    }
    XCTAssertEqual(options.delta, 10_000)
  }

  // MARK: - Targets that cannot drag

  /// A drag needs the HID stack, so the executor refuses one on anything but a simulator. This pins
  /// the sentence a device caller reads: `errorDescription` is what `localizedDescription` returns,
  /// and so what grpc-swift puts on the wire.
  ///
  /// It does not pin the guard to the drag path -- reaching `accessibility_drag` needs an
  /// `FBIDBCommandExecutor`, which needs a live `FBiOSTarget & AsynciOSTarget`. See the test plan.
  func testADragOnANonSimulatorNamesTheOperationAndTheTarget() {
    let error = FBIDBCommandError.simulatorOnlyOperation(
      operation: "drag by accessibility", targetDescription: "iPhone 15 | Booted | iOS 17.0")
    XCTAssertEqual(
      error.errorDescription,
      "Target is not a simulator, cannot drag by accessibility: iPhone 15 | Booted | iOS 17.0")
  }
}

/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import XCTest

private let inner = SimulatorDisplay(
  uniqueID: "inner", name: "inner", activity: .active, isPrimary: false, isIntegrated: true,
  bounds: CGRect(x: 0, y: 0, width: 1206, height: 2622), scale: 3, rotation: .upright)

private struct Failure: Error {}

private func capture(
  resolveDisplay: () async throws -> SimulatorDisplayResolution = { .target(.selected(inner)) },
  display: (SimulatorDisplay) async throws -> String = { "display \($0.uniqueID)" },
  mainScreen: () async throws -> String = { "main screen" },
  logger: CapturingLogger = CapturingLogger()
) async throws -> String {
  try await SimulatorScreenshotCommands.capture(resolveDisplay: resolveDisplay, display: display, mainScreen: mainScreen, logger: logger)
}

final class SimulatorScreenshotCommandsTests: XCTestCase {
  func testActiveDisplayIsCaptured() async throws {
    let captured = try await capture()
    XCTAssertEqual(captured, "display inner")
  }

  func testActiveDisplayFailures() async throws {
    let logger = CapturingLogger()
    let unselected = try await capture(resolveDisplay: { throw Failure() }, logger: logger)
    XCTAssertEqual(unselected, "main screen")
    let uncaptured = try await capture(display: { _ in throw Failure() }, logger: logger)
    XCTAssertEqual(uncaptured, "main screen")
    XCTAssertEqual(logger.messages.count, 2)
  }

  func testOnlyAnIdentifiedActiveDisplayIsCaptured() async throws {
    let lcd = SimulatorDisplay(
      uniqueID: "lcd", name: "lcd", activity: .inactive, isPrimary: true, isIntegrated: true, bounds: inner.bounds, scale: 3,
      rotation: .upright)
    let resolutions: [(SimulatorDisplayResolution, String)] = [
      (.target(.sole(.identified(inner))), "display inner"),
      (.target(.sole(.identified(lcd))), "main screen"),
      (.target(.sole(.legacy(inner.geometry))), "main screen"),
      (.fallback(.noActiveIntegratedDisplay), "main screen"),
      (.transitioning, "main screen"),
    ]
    for (resolution, expected) in resolutions {
      let captured = try await capture(resolveDisplay: { resolution })
      XCTAssertEqual(captured, expected, "\(resolution)")
    }
  }

  func testCancellationIsNotAFallback() async {
    do {
      _ = try await capture(resolveDisplay: { throw CancellationError() })
      XCTFail("Expected cancellation")
    } catch { XCTAssertTrue(error is CancellationError) }
  }

  func testMainScreenFailureFailsTheScreenshot() async {
    do {
      _ = try await capture(resolveDisplay: { throw Failure() }, mainScreen: { throw Failure() })
      XCTFail("Expected the main screen failure")
    } catch { XCTAssertTrue(error is Failure) }
  }
}

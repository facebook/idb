/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import XCTest

private let inner = SimulatorDisplay(
  uniqueID: "inner", name: "inner", isActive: true, isPrimary: false, isIntegrated: true,
  bounds: CGRect(x: 0, y: 0, width: 1206, height: 2622), scale: 3, rotation: .upright)

private struct Failure: Error {}

private func capture(
  activeDisplay: () async throws -> SimulatorDisplay? = { inner },
  display: (SimulatorDisplay) async throws -> String = { "display \($0.uniqueID)" },
  mainScreen: () async throws -> String = { "main screen" },
  logger: CapturingLogger = CapturingLogger()
) async throws -> String {
  try await SimulatorScreenshotCommands.capture(activeDisplay: activeDisplay, display: display, mainScreen: mainScreen, logger: logger)
}

final class SimulatorScreenshotCommandsTests: XCTestCase {
  func testActiveDisplayIsCaptured() async throws {
    let captured = try await capture()
    XCTAssertEqual(captured, "display inner")
  }

  func testMainScreenIsCapturedWithoutAnActiveDisplay() async throws {
    let captured = try await capture(activeDisplay: { nil })
    XCTAssertEqual(captured, "main screen")
  }

  func testActiveDisplayFailures() async throws {
    let logger = CapturingLogger()
    let unselected = try await capture(activeDisplay: { throw Failure() }, logger: logger)
    XCTAssertEqual(unselected, "main screen")
    let uncaptured = try await capture(display: { _ in throw Failure() }, logger: logger)
    XCTAssertEqual(uncaptured, "main screen")
    XCTAssertEqual(logger.messages.count, 2)
  }

  func testCancellationIsNotAFallback() async {
    do {
      _ = try await capture(activeDisplay: { throw CancellationError() })
      XCTFail("Expected cancellation")
    } catch { XCTAssertTrue(error is CancellationError) }
  }

  func testMainScreenFailureFailsTheScreenshot() async {
    do {
      _ = try await capture(activeDisplay: { nil }, mainScreen: { throw Failure() })
      XCTFail("Expected the main screen failure")
    } catch { XCTAssertTrue(error is Failure) }
  }
}

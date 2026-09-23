/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Foundation
import XCTest

final class FramebufferSurfaceLocatorTests: XCTestCase {

  func testDeliversTheReportedScreens() async throws {
    let screens = try await FramebufferSurfaceLocator.reportedScreens(timeout: 5) { report in
      DispatchQueue.global().async { report(["a", "b"]) }
    }
    XCTAssertEqual(screens as? [String], ["a", "b"])
  }

  func testDeliversAReportMadeBeforeTheCallSuspends() async throws {
    let screens = try await FramebufferSurfaceLocator.reportedScreens(timeout: 5) { report in
      report(["a"])
    }
    XCTAssertEqual(screens as? [String], ["a"])
  }

  func testOnlyTheFirstReportCounts() async throws {
    let screens = try await FramebufferSurfaceLocator.reportedScreens(timeout: 5) { report in
      report(["first"])
      report(["second"])
    }
    XCTAssertEqual(screens as? [String], ["first"])
  }

  func testRethrowsAFailureToStartTheEnumeration() async {
    struct Failure: Error {}
    do {
      _ = try await FramebufferSurfaceLocator.reportedScreens(timeout: 5) { _ in throw Failure() }
      XCTFail("Expected the start failure to be rethrown")
    } catch is Failure {
    } catch {
      XCTFail("Unexpected error \(error)")
    }
  }

  func testTimesOutWhenNothingIsReported() async {
    do {
      _ = try await FramebufferSurfaceLocator.reportedScreens(timeout: 0.05) { _ in }
      XCTFail("Expected the deadline to fire")
    } catch SimulatorDisplayError.screensNotReported(let seconds) {
      XCTAssertEqual(seconds, 0.05)
    } catch {
      XCTFail("Unexpected error \(error)")
    }
  }

  func testAReportAfterTheDeadlineIsIgnored() async throws {
    let reported = expectation(description: "the late report was made")
    do {
      _ = try await FramebufferSurfaceLocator.reportedScreens(timeout: 0.05) { report in
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
          report(["late"])
          reported.fulfill()
        }
      }
      XCTFail("Expected the deadline to fire")
    } catch SimulatorDisplayError.screensNotReported {
    }
    // A second resume would trap, so the late report landing harmlessly is the assertion.
    await fulfillment(of: [reported], timeout: 2)
  }
}

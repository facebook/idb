/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import XCTest

final class SimulatorLifecycleErrorTests: XCTestCase {

  private let url = URL(string: "https://fbidb.io/docs/idb")!

  func testOpenURLFailedWithAReasonGivesTheReason() {
    let underlying = NSError(domain: NSPOSIXErrorDomain, code: 60, userInfo: [NSLocalizedDescriptionKey: "Operation timed out"])
    let error = SimulatorLifecycleError.openURLFailed(url: url, simulatorDescription: "iPhone 16", underlying: underlying)
    XCTAssertEqual(error.errorDescription, "Failed to open URL https://fbidb.io/docs/idb on simulator iPhone 16: \(underlying)")
  }

  func testOpenURLFailedWithoutAReasonOmitsIt() {
    let error = SimulatorLifecycleError.openURLFailed(url: url, simulatorDescription: "iPhone 16", underlying: nil)
    XCTAssertEqual(error.errorDescription, "Failed to open URL https://fbidb.io/docs/idb on simulator iPhone 16")
  }
}

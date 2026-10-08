/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBAXCore
@testable import FBSimulatorAX
import XCTest

/// The backend names that decide which guest a UI automation reads through.
final class UIAutomationBackendNameTests: XCTestCase {
  func testEveryResolvedBackendNameRoundTrips() {
    let cases: [(AXBridgePersistence, UIAutomationBackendName)] = [
      (.oneShot, .axBridgeOneShot), (.shared, .axBridgePersistent), (.exclusive, .axBridgeExclusive),
    ]
    for (persistence, name) in cases {
      let backend = UIAutomationBackend.axBridge(
        persistence: persistence, frontmostMethod: .windowServer, automationMode: true)
      XCTAssertEqual(backend.name, name)
      XCTAssertEqual(UIAutomationBackend(resolvedName: name), backend)
    }
  }

  func testTheOneShotCaseHasAnExplicitWireName() {
    XCTAssertEqual(UIAutomationBackendName.axBridgeOneShot.rawValue, "axbridge-oneshot")
  }

  func testTheSharedCaseKeepsTheExistingWireName() {
    XCTAssertEqual(UIAutomationBackendName.axBridgePersistent.rawValue, "axbridge-persistent")
  }

  func testTheExclusiveCaseHasItsOwnWireName() {
    XCTAssertEqual(UIAutomationBackendName.axBridgeExclusive.rawValue, "axbridge-exclusive")
  }
}

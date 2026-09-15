/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
@_implementationOnly import SimulatorFrameworkBridgeLib
import XCTest

final class DnsServiceTests: XCTestCase {

  // MARK: - buildDnsDict

  func testBuildDnsDictMultipleServers() {
    let dict = buildDnsDict(["8.8.8.8", "8.8.4.4", "1.1.1.1"])

    let servers = dict["ServerAddresses"] as? [String]
    XCTAssertEqual(servers?.count ?? 0, 3)
    XCTAssertEqual(servers?[0], "8.8.8.8")
    XCTAssertEqual(servers?[1], "8.8.4.4")
    XCTAssertEqual(servers?[2], "1.1.1.1")
  }

  // MARK: - handleDnsAction

  // `SCDynamicStoreCreate` returns NULL for a sandboxed app, and an XCTest bundle runs inside
  // one, so no action that needs a store can get past that point here. In production the bridge
  // is `simctl spawn`'d rather than launched as an app and does get a store, which is why these
  // tests can only pin the store-unavailable path. Everything above this point is pure and is
  // covered for real.
  func testHandleDnsActionListReturnsFailureWithoutADynamicStore() {
    let result = handleDnsAction("list", [])
    XCTAssertEqual(result, 1)
  }

  func testHandleDnsActionSetMissingArgsReturnsFailure() {
    XCTAssertEqual(handleDnsAction("set", []), 1)
  }

  func testHandleDnsActionUnknownActionReturnsFailure() {
    XCTAssertEqual(handleDnsAction("unknown", []), 1)
  }
}

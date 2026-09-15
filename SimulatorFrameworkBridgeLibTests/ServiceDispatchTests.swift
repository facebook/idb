/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@_implementationOnly import SimulatorFrameworkBridgeLib
import XCTest

final class ServiceDispatchTests: XCTestCase {

  // MARK: - Unknown service

  func testUnknownServiceReturnsFailure() {
    XCTAssertEqual(dispatchService("unknown", "clear", []), 1)
  }

  // MARK: - Contacts routing

  func testDispatchContactsUnknownAction() {
    XCTAssertEqual(dispatchService("contacts", "unknown", []), 1)
  }

  // MARK: - Photos routing

  func testDispatchPhotosUnknownAction() {
    XCTAssertEqual(dispatchService("photos", "unknown", []), 1)
  }

  // MARK: - Notifications routing

  func testDispatchNotificationsRoutes() {
    XCTAssertEqual(dispatchService("notifications", "approve", ["com.test"]), 0)
  }

  func testDispatchNotificationsPassesBundleID() {
    XCTAssertEqual(dispatchService("notifications", "check", ["com.test"]), 0)
  }

  func testDispatchNotificationsNoBundleID() {
    // "list" with no arguments — bundleID is nil, so every section is reported
    XCTAssertEqual(dispatchService("notifications", "list", []), 0)
  }

  // MARK: - Proxy routing

  func testDispatchProxyMissingArgsRoutes() {
    // "set" with no args → insufficient arguments error
    XCTAssertEqual(dispatchService("proxy", "set", []), 1)
  }

  func testDispatchProxyUnknownAction() {
    XCTAssertEqual(dispatchService("proxy", "unknown", []), 1)
  }

  // MARK: - DNS routing

  func testDispatchDnsMissingArgsRoutes() {
    XCTAssertEqual(dispatchService("dns", "set", []), 1)
  }

  func testDispatchDnsUnknownAction() {
    XCTAssertEqual(dispatchService("dns", "unknown", []), 1)
  }

  // MARK: - Health routing

  func testDispatchHealthRoutes() {
    // "list" for this bundle ID answers 1
    XCTAssertEqual(dispatchService("health", "list", ["com.test"]), 1)
  }

  func testDispatchHealthNoBundleID() {
    // "list" with no arguments — bundleID is nil, which answers 1
    XCTAssertEqual(dispatchService("health", "list", []), 1)
  }
}

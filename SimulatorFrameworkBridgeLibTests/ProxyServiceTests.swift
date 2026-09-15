/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
@_implementationOnly import SimulatorFrameworkBridgeLib
import XCTest

final class ProxyServiceTests: XCTestCase {

  func testUnknownActionReturnsFailure() {
    XCTAssertEqual(handleProxyAction("unknown", []), 1)
    XCTAssertEqual(handleProxyAction("", []), 1)
    XCTAssertEqual(handleProxyAction("remove", []), 1)
  }

  func testSetWithNoArgsReturnsFailure() {
    XCTAssertEqual(handleProxyAction("set", []), 1)
  }

  func testSetWithOneArgReturnsFailure() {
    XCTAssertEqual(handleProxyAction("set", ["127.0.0.1"]), 1)
  }

  // MARK: - buildHTTPProxyDict

  func testBuildHTTPProxyDictContainsHTTPKeys() {
    let dict = buildHTTPProxyDict("10.0.0.1", 8080)
    XCTAssertNotNil(dict)

    XCTAssertEqual(dict["HTTPProxy"] as? String, "10.0.0.1")
    XCTAssertEqual(dict["HTTPPort"] as? NSNumber, 8080)
    XCTAssertEqual(dict["HTTPEnable"] as? NSNumber, 1)
  }

  func testBuildHTTPProxyDictContainsHTTPSKeys() {
    let dict = buildHTTPProxyDict("proxy.example.com", 3128)

    XCTAssertEqual(dict["HTTPSProxy"] as? String, "proxy.example.com")
    XCTAssertEqual(dict["HTTPSPort"] as? NSNumber, 3128)
    XCTAssertEqual(dict["HTTPSEnable"] as? NSNumber, 1)
  }

  func testBuildHTTPProxyDictContainsFTPPassiveAndExceptions() {
    let dict = buildHTTPProxyDict("127.0.0.1", 8080)

    XCTAssertEqual(dict["FTPPassive"] as? NSNumber, 1)
    let exceptions = dict["ExceptionsList"] as? [String]
    XCTAssertEqual(exceptions?.count ?? 0, 2)
    XCTAssertTrue(exceptions?.contains("*.local") ?? false)
    XCTAssertTrue(exceptions?.contains("169.254/16") ?? false)
  }

  // MARK: - buildSOCKSProxyDict

  func testBuildSOCKSProxyDictContainsSOCKSKeys() {
    let dict = buildSOCKSProxyDict("10.0.0.1", 1080)
    XCTAssertNotNil(dict)

    XCTAssertEqual(dict["SOCKSProxy"] as? String, "10.0.0.1")
    XCTAssertEqual(dict["SOCKSPort"] as? NSNumber, 1080)
    XCTAssertEqual(dict["SOCKSEnable"] as? NSNumber, 1)
  }

  func testBuildSOCKSProxyDictDoesNotContainHTTPKeys() {
    let dict = buildSOCKSProxyDict("10.0.0.1", 1080)

    XCTAssertNil(dict["HTTPProxy"])
    XCTAssertNil(dict["HTTPPort"])
    XCTAssertNil(dict["HTTPEnable"])
    XCTAssertNil(dict["HTTPSProxy"])
    XCTAssertNil(dict["HTTPSPort"])
    XCTAssertNil(dict["HTTPSEnable"])
  }

  func testBuildSOCKSProxyDictContainsFTPPassiveAndExceptions() {
    let dict = buildSOCKSProxyDict("10.0.0.1", 1080)

    XCTAssertEqual(dict["FTPPassive"] as? NSNumber, 1)
    let exceptions = dict["ExceptionsList"] as? [String]
    XCTAssertEqual(exceptions?.count ?? 0, 2)
    XCTAssertTrue(exceptions?.contains("*.local") ?? false)
    XCTAssertTrue(exceptions?.contains("169.254/16") ?? false)
  }

  // MARK: - buildEmptyProxyDict

  func testBuildEmptyProxyDictContainsOnlyFTPPassive() {
    let dict = buildEmptyProxyDict()
    XCTAssertNotNil(dict)

    XCTAssertEqual(dict.count, 1)
    XCTAssertEqual(dict["FTPPassive"] as? NSNumber, 1)
  }

  // MARK: - handleProxyAction list

  // See the note in DnsServiceTests: a sandboxed XCTest host cannot create an SCDynamicStore,
  // so `list` reports failure here where the `simctl spawn`'d bridge would succeed.
  func testHandleProxyActionListReturnsFailureWithoutADynamicStore() {
    let result = handleProxyAction("list", [])
    XCTAssertEqual(result, 1)
  }
}

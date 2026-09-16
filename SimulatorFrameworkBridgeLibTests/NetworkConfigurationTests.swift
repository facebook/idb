/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import XCTest

final class NetworkConfigurationTests: XCTestCase {
  private func key(_ service: String) -> String {
    service == "dns" ? "State:/Network/Global/DNS" : "State:/Network/Global/Proxies"
  }

  func testDNSWritesAllServersAndNotifiesAfterTheWrite() {
    let runtime = FBNetworkConfigurationTestRuntime()
    XCTAssertEqual(runtime.run(service: "dns", action: "set", arguments: ["8.8.8.8", "1.1.1.1"]), 0)
    XCTAssertEqual(runtime.writes as NSArray, [["ServerAddresses": ["8.8.8.8", "1.1.1.1"]]] as NSArray)
    XCTAssertEqual(runtime.keys as NSArray, [key("dns"), key("dns")] as NSArray)
    XCTAssertEqual(
      runtime.operations as NSArray,
      [
        "load", "lookup:SCDynamicStoreCreate", "create:SimulatorFrameworkBridge.dns",
        "lookup:SCDynamicStoreSetValue", "lookup:SCDynamicStoreNotifyValue", "write", "notify",
      ] as NSArray)
    XCTAssertEqual(runtime.output, "")
  }

  func testProxyDefaultsAndUnknownTypesUseHTTP() {
    for suffix in [[], ["http"], ["unknown"], ["HTTP"], ["http", "ignored"]] {
      let runtime = FBNetworkConfigurationTestRuntime()
      XCTAssertEqual(runtime.run(service: "proxy", action: "set", arguments: ["localhost", "8080"] + suffix), 0)
      XCTAssertEqual(
        runtime.writes as NSArray,
        [
          [
            "HTTPEnable": 1, "HTTPProxy": "localhost", "HTTPPort": 8080,
            "HTTPSEnable": 1, "HTTPSProxy": "localhost", "HTTPSPort": 8080,
            "FTPPassive": 1, "ExceptionsList": ["*.local", "169.254/16"],
          ]
        ] as NSArray)
      XCTAssertEqual(runtime.keys as NSArray, [key("proxy"), key("proxy")] as NSArray)
      XCTAssertEqual(Array(runtime.operations.suffix(2)) as NSArray, ["write", "notify"] as NSArray)
    }
  }

  func testSOCKSAndPermissivePortParsing() {
    for (text, port) in [("123junk", 123), ("invalid", 0), ("-9", -9), (" +42", 42)] {
      let runtime = FBNetworkConfigurationTestRuntime()
      XCTAssertEqual(runtime.run(service: "proxy", action: "set", arguments: ["host", text, "socks"]), 0)
      XCTAssertEqual(
        runtime.writes as NSArray,
        [
          [
            "SOCKSEnable": 1, "SOCKSProxy": "host", "SOCKSPort": port,
            "FTPPassive": 1, "ExceptionsList": ["*.local", "169.254/16"],
          ]
        ] as NSArray)
    }
  }

  func testClearWritesServiceSpecificEmptyConfiguration() {
    for service in ["dns", "proxy"] {
      let runtime = FBNetworkConfigurationTestRuntime()
      XCTAssertEqual(runtime.run(service: service, action: "clear", arguments: []), 0)
      let expected: [String: Any] = service == "dns" ? [:] : ["FTPPassive": 1]
      XCTAssertEqual(runtime.writes as NSArray, [expected] as NSArray)
      XCTAssertEqual(runtime.keys as NSArray, [key(service), key(service)] as NSArray)
    }
  }

  func testListDoesNotRequireWriteSymbols() throws {
    for service in ["dns", "proxy"] {
      let runtime = FBNetworkConfigurationTestRuntime()
      runtime.missingSymbols = ["SCDynamicStoreSetValue", "SCDynamicStoreNotifyValue"]
      runtime.configuration = ["value": ["first", "second"]]
      XCTAssertEqual(runtime.run(service: service, action: "list", arguments: []), 0)
      let json = try JSONSerialization.jsonObject(with: Data(runtime.output.utf8))
      XCTAssertEqual(json as? NSDictionary, ["value": ["first", "second"]] as NSDictionary)
      XCTAssertTrue(runtime.output.hasSuffix("\n"))
      XCTAssertEqual(runtime.keys as NSArray, [key(service)] as NSArray)
      XCTAssertEqual(runtime.writes.count, 0)
      XCTAssertFalse(runtime.operations.contains("lookup:SCDynamicStoreSetValue"))
      XCTAssertFalse(runtime.operations.contains("notify"))
    }
  }

  func testMissingListConfigurationPrintsEmptyObject() {
    for service in ["dns", "proxy"] {
      let runtime = FBNetworkConfigurationTestRuntime()
      XCTAssertEqual(runtime.run(service: service, action: "list", arguments: []), 0)
      XCTAssertEqual(runtime.output, "{}\n")
      XCTAssertEqual(runtime.keys as NSArray, [key(service)] as NSArray)
    }
  }

  func testRejectedCommandsDoNotWriteToAnAvailableStore() {
    for (service, action, arguments) in [
      ("dns", "set", []), ("proxy", "set", []), ("proxy", "set", ["host"]),
      ("dns", "unknown", []), ("proxy", "unknown", []),
    ] {
      let runtime = FBNetworkConfigurationTestRuntime()
      XCTAssertEqual(runtime.run(service: service, action: action, arguments: arguments), 1)
      XCTAssertTrue(runtime.operations.contains("lookup:SCDynamicStoreSetValue"))
      XCTAssertEqual(runtime.writes.count, 0)
      XCTAssertEqual(runtime.keys.count, 0)
      XCTAssertEqual(runtime.output, "")
    }
  }

  func testMissingFrameworkStoreAndRequiredSymbolsFailBeforeIO() {
    for service in ["dns", "proxy"] {
      for failure in ["library", "store", "SCDynamicStoreCreate", "SCDynamicStoreCopyValue", "SCDynamicStoreSetValue"] {
        let runtime = FBNetworkConfigurationTestRuntime()
        runtime.libraryAvailable = failure != "library"
        runtime.storeAvailable = failure != "store"
        runtime.missingSymbols = [failure]
        let action = failure == "SCDynamicStoreCopyValue" ? "list" : "clear"
        XCTAssertEqual(runtime.run(service: service, action: action, arguments: []), 1)
        XCTAssertEqual(runtime.keys.count, 0)
        XCTAssertEqual(runtime.writes.count, 0)
        XCTAssertEqual(runtime.output, "")
      }
    }
    let runtime = FBNetworkConfigurationTestRuntime()
    runtime.missingSymbols = ["SCDynamicStoreKeyCreateProxies"]
    XCTAssertEqual(runtime.run(service: "proxy", action: "clear", arguments: []), 1)
    XCTAssertFalse(runtime.operations.contains("create:SimulatorFrameworkBridge.proxy"))
  }

  func testFailedWriteDoesNotNotify() {
    for service in ["dns", "proxy"] {
      let runtime = FBNetworkConfigurationTestRuntime()
      runtime.writeSucceeds = false
      XCTAssertEqual(runtime.run(service: service, action: "clear", arguments: []), 1)
      XCTAssertEqual(runtime.writes.count, 1)
      XCTAssertEqual(runtime.keys as NSArray, [key(service)] as NSArray)
      XCTAssertFalse(runtime.operations.contains("notify"))
    }
  }

  func testOptionalNotificationDoesNotChangeWriteSuccess() {
    for service in ["dns", "proxy"] {
      for available in [true, false] {
        let runtime = FBNetworkConfigurationTestRuntime()
        runtime.notifySucceeds = false
        runtime.missingSymbols = available ? [] : ["SCDynamicStoreNotifyValue"]
        XCTAssertEqual(runtime.run(service: service, action: "clear", arguments: []), 0)
        XCTAssertEqual(runtime.writes.count, 1)
        XCTAssertEqual(runtime.operations.contains("notify"), available)
      }
    }
  }
}

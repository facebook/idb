/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
@_implementationOnly import SimulatorFrameworkBridgeLib
import XCTest

final class DynamicStoreServiceTests: XCTestCase {
  private let dnsKey = "State:/Network/Global/DNS"
  private let proxyKey = "State:/Network/Global/Proxies"

  private func encoded(_ object: Any) throws -> Data {
    try PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0)
  }

  private func decoded(_ data: Data) throws -> NSDictionary {
    try XCTUnwrap(
      PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? NSDictionary)
  }

  /** The reads and writes the service made, without the session setup that precedes them. */
  private func storeOperations(_ runtime: FBDynamicStoreTestRuntime) -> NSArray {
    runtime.operations
      .compactMap { $0 as? String }
      .filter { $0 != "load" && !$0.hasPrefix("lookup:") && !$0.hasPrefix("create:") } as NSArray
  }

  // MARK: - Keys

  func testTheAliasesNameTheTwoGlobalKeysAndAKeyIsTakenAsGiven() {
    XCTAssertEqual(dynamicStoreKeyForName("dns"), dnsKey)
    XCTAssertEqual(dynamicStoreKeyForName("proxy"), proxyKey)
    XCTAssertEqual(dynamicStoreKeyForName("Setup:/Network/Service/A"), "Setup:/Network/Service/A")
    XCTAssertNil(dynamicStoreKeyForName("something"))
  }

  // MARK: - Snapshot

  func testSnapshotOfAPresentValueWritesItUnderTheAliasedKey() throws {
    let runtime = FBDynamicStoreTestRuntime()
    runtime.value = ["ServerAddresses": ["8.8.8.8"]]

    XCTAssertEqual(runtime.run(action: "snapshot", arguments: ["dns"], input: nil), 0)

    XCTAssertEqual(
      try decoded(runtime.output),
      ["present": true, "value": ["ServerAddresses": ["8.8.8.8"]]] as NSDictionary)
    XCTAssertEqual(runtime.keys as NSArray, [dnsKey] as NSArray)
  }

  func testSnapshotOfAnAbsentKeyReportsItAbsentRatherThanFailing() throws {
    let runtime = FBDynamicStoreTestRuntime()

    XCTAssertEqual(runtime.run(action: "snapshot", arguments: ["proxy"], input: nil), 0)

    XCTAssertEqual(try decoded(runtime.output), ["present": false] as NSDictionary)
    XCTAssertEqual(runtime.keys as NSArray, [proxyKey] as NSArray)
  }

  // A failed read copies NULL exactly as an absent key does, so reporting it as absent would let a
  // test restore emptiness over a value that was there all along.
  func testAFailedReadIsNotReportedAsAnAbsentKey() {
    let runtime = FBDynamicStoreTestRuntime()
    runtime.errorStatus = 1001

    XCTAssertEqual(runtime.run(action: "snapshot", arguments: ["dns"], input: nil), 1)

    XCTAssertEqual(runtime.output, Data())
  }

  func testARawKeyIsReadAsGiven() throws {
    let runtime = FBDynamicStoreTestRuntime()
    runtime.value = ["Addresses": ["192.0.2.1"]]

    XCTAssertEqual(
      runtime.run(action: "snapshot", arguments: ["State:/Network/Interface/en0/IPv4"], input: nil), 0)

    XCTAssertEqual(runtime.keys as NSArray, ["State:/Network/Interface/en0/IPv4"] as NSArray)
  }

  // MARK: - Restore

  func testRestoringAValueWritesItNotifiesAndAnswersWithWhatItReadBack() throws {
    let runtime = FBDynamicStoreTestRuntime()
    runtime.value = ["ServerAddresses": ["192.0.2.1"]]
    let snapshot = try encoded(["present": true, "value": ["ServerAddresses": ["8.8.8.8"]]])

    XCTAssertEqual(runtime.run(action: "restore", arguments: ["dns"], input: snapshot), 0)

    XCTAssertEqual(runtime.value as? NSDictionary, ["ServerAddresses": ["8.8.8.8"]] as NSDictionary)
    XCTAssertEqual(
      try decoded(runtime.output),
      ["present": true, "value": ["ServerAddresses": ["8.8.8.8"]]] as NSDictionary)
    XCTAssertEqual(storeOperations(runtime), ["read", "write", "notify", "read"] as NSArray)
  }

  func testRestoringAnAbsentSnapshotRemovesTheValueThatIsThere() throws {
    let runtime = FBDynamicStoreTestRuntime()
    runtime.value = ["HTTPEnable": 1]
    let snapshot = try encoded(["present": false])

    XCTAssertEqual(runtime.run(action: "restore", arguments: ["proxy"], input: snapshot), 0)

    XCTAssertNil(runtime.value)
    XCTAssertEqual(try decoded(runtime.output), ["present": false] as NSDictionary)
    XCTAssertEqual(storeOperations(runtime), ["read", "remove", "notify", "read"] as NSArray)
  }

  // Removing a key that is not there is an error in configd, and the key being absent is the state
  // the snapshot asks for, so there is nothing to undo.
  func testRestoringAnAbsentSnapshotOverAnAbsentKeyRemovesNothing() throws {
    let runtime = FBDynamicStoreTestRuntime()
    let snapshot = try encoded(["present": false])

    XCTAssertEqual(runtime.run(action: "restore", arguments: ["proxy"], input: snapshot), 0)

    XCTAssertFalse(runtime.operations.contains("remove"))
    XCTAssertEqual(try decoded(runtime.output), ["present": false] as NSDictionary)
    XCTAssertEqual(storeOperations(runtime), ["read", "notify", "read"] as NSArray)
  }

  func testAFailedWriteIsReportedRatherThanAnsweredWithTheOldValue() throws {
    let runtime = FBDynamicStoreTestRuntime()
    runtime.writeSucceeds = false
    let snapshot = try encoded(["present": true, "value": ["ServerAddresses": ["8.8.8.8"]]])

    XCTAssertEqual(runtime.run(action: "restore", arguments: ["dns"], input: snapshot), 1)

    XCTAssertEqual(runtime.output, Data())
  }

  // MARK: - Arguments

  func testAnUnreadableSnapshotIsRefused() throws {
    for input in [Data(), Data("not a property list".utf8), try encoded(["value": [:]])] {
      let runtime = FBDynamicStoreTestRuntime()

      XCTAssertEqual(runtime.run(action: "restore", arguments: ["dns"], input: input), 1)

      XCTAssertFalse(runtime.operations.contains("write"))
    }
  }

  func testASnapshotThatIsPresentWithNoValueIsRefused() throws {
    let runtime = FBDynamicStoreTestRuntime()
    let snapshot = try encoded(["present": true])

    XCTAssertEqual(runtime.run(action: "restore", arguments: ["dns"], input: snapshot), 1)

    XCTAssertFalse(runtime.operations.contains("write"))
  }

  func testAnUnknownNameOrActionIsRefusedBeforeTheStoreIsOpened() {
    for (action, arguments) in [("snapshot", ["something"]), ("snapshot", []), ("erase", ["dns"])] {
      let runtime = FBDynamicStoreTestRuntime()

      XCTAssertEqual(runtime.run(action: action, arguments: arguments, input: nil), 1)

      XCTAssertEqual(runtime.operations as NSArray, [] as NSArray)
    }
  }

  func testAMissingRemoveSymbolIsReportedRatherThanSilentlySkipped() throws {
    let runtime = FBDynamicStoreTestRuntime()
    runtime.value = ["HTTPEnable": 1]
    runtime.missingSymbols = ["SCDynamicStoreRemoveValue"]
    let snapshot = try encoded(["present": false])

    XCTAssertEqual(runtime.run(action: "restore", arguments: ["proxy"], input: snapshot), 1)

    XCTAssertEqual(runtime.value as? NSDictionary, ["HTTPEnable": 1] as NSDictionary)
  }
}

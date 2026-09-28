/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
import Foundation
import SimulatorIPC
import XCTest

final class IPCDirectoryWatchTests: XCTestCase {
  private var directory = ""

  override func setUpWithError() throws {
    directory = "/tmp/ipc-\(UUID().uuidString.prefix(8))"
    try IPCSocket.prepareDirectory(directory)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(atPath: directory)
  }

  func testAListenerBoundAfterTheWatchStartsWakesIt() throws {
    let watch = IPCDirectoryWatch(directory: directory)
    let listener = try XCTUnwrap(try IPCListener.bind(path: "\(directory)/s.sock", backlog: 1))

    XCTAssertTrue(watch.wait(timeoutMilliseconds: 1_000))
    withExtendedLifetime(listener) {}
  }

  func testAReleasedListenerWakesIt() throws {
    var listener = try IPCListener.bind(path: "\(directory)/s.sock", backlog: 1)
    XCTAssertNotNil(listener)
    let watch = IPCDirectoryWatch(directory: directory)
    listener = nil

    XCTAssertTrue(watch.wait(timeoutMilliseconds: 1_000))
  }

  func testAQuietDirectoryTimesOut() {
    let watch = IPCDirectoryWatch(directory: directory)
    let started = Date()

    XCTAssertFalse(watch.wait(timeoutMilliseconds: 100))
    XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started), 0.1)
  }

  func testAMissingDirectoryIsWatchedThroughItsParent() {
    let missing = "\(directory)/missing"
    let watch = IPCDirectoryWatch(directory: missing)
    XCTAssertEqual(mkdir(missing, 0o700), 0)

    XCTAssertTrue(watch.wait(timeoutMilliseconds: 1_000))
  }
}

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

final class IPCSocketTests: XCTestCase {
  private var directory = ""

  override func setUpWithError() throws {
    directory = "/tmp/ipc-\(UUID().uuidString.prefix(8))"
    try IPCSocket.prepareDirectory(directory)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(atPath: directory)
  }

  func testFramesRoundTripBetweenAListenerAndAClient() throws {
    let path = "\(directory)/s.sock"
    let listener = try XCTUnwrap(IPCListener.bind(path: path, backlog: 1))
    let client = try XCTUnwrap(IPCSocket.connect(path: path, timeoutSeconds: 5))
    defer { close(client) }
    let server = accept(listener.fileDescriptor, nil, nil)
    XCTAssertGreaterThanOrEqual(server, 0)
    defer { close(server) }

    try IPCSocket.writeFrame(client, Data("ping".utf8))
    XCTAssertEqual(try IPCSocket.readFrame(server), Data("ping".utf8))
    try IPCSocket.writeFrame(server, Data("pong".utf8))
    XCTAssertEqual(try IPCSocket.readFrame(client), Data("pong".utf8))
  }

  func testReadingFromAClosedPeerReportsClosed() throws {
    var descriptors: [Int32] = [0, 0]
    XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors), 0)
    defer { close(descriptors[0]) }
    close(descriptors[1])

    XCTAssertThrowsError(try IPCSocket.readFrame(descriptors[0])) {
      XCTAssertEqual($0 as? IPCError, .closed)
    }
  }

  func testASilentPeerTimesOut() throws {
    var descriptors: [Int32] = [0, 0]
    XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors), 0)
    defer {
      close(descriptors[0])
      close(descriptors[1])
    }
    IPCSocket.setTimeout(descriptors[0], seconds: 1)

    XCTAssertThrowsError(try IPCSocket.readFrame(descriptors[0])) {
      XCTAssertEqual($0 as? IPCError, .timedOut)
    }
  }

  func testASecondListenerOnTheSamePathDefersToTheFirst() throws {
    let path = "\(directory)/s.sock"
    let first = try XCTUnwrap(IPCListener.bind(path: path, backlog: 1))

    XCTAssertNil(try IPCListener.bind(path: path, backlog: 1))
    withExtendedLifetime(first) {
      XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }
  }

  func testReleasingAListenerRemovesItsSocket() throws {
    let path = "\(directory)/s.sock"
    _ = try XCTUnwrap(IPCListener.bind(path: path, backlog: 1))

    XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    XCTAssertNil(try IPCSocket.connect(path: path, timeoutSeconds: 1))
  }

  func testAPathLongerThanSockaddrIsRefused() {
    let path = "/tmp/" + String(repeating: "x", count: IPCSocket.pathCapacity)

    XCTAssertThrowsError(try IPCSocket.connect(path: path, timeoutSeconds: 1)) {
      XCTAssertEqual($0 as? IPCError, .pathTooLong(path: path, limit: IPCSocket.pathCapacity))
    }
    XCTAssertThrowsError(try IPCListener.bind(path: path, backlog: 1))
  }

  func testPreparedDirectoriesAreOwnerOnly() throws {
    let loose = "\(directory)/loose"
    XCTAssertEqual(mkdir(loose, 0o777), 0)
    try IPCSocket.prepareDirectory(loose)

    let mode = try FileManager.default.attributesOfItem(atPath: loose)[.posixPermissions] as? Int
    XCTAssertEqual(mode, IPCSocket.ownerOnlyPermissions)
  }
}

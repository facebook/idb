/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
import Foundation
import SimulatorIPC
import Testing

@Suite(.serialized)
final class IPCSocketTests {
  private let directory: String

  init() throws {
    directory = "/tmp/ipc-\(UUID().uuidString.prefix(8))"
    try IPCSocket.prepareDirectory(directory)
  }

  deinit {
    try? FileManager.default.removeItem(atPath: directory)
  }

  @Test
  func framesRoundTripBetweenAListenerAndAClient() throws {
    let path = "\(directory)/s.sock"
    let listener = try #require(try IPCListener.bind(path: path, backlog: 1))
    let client = try #require(try IPCSocket.connect(path: path, timeoutSeconds: 5))
    defer { close(client) }
    let server = accept(listener.fileDescriptor, nil, nil)
    #expect(server >= 0)
    defer { close(server) }

    try IPCSocket.writeFrame(client, Data("ping".utf8))
    #expect(try IPCSocket.readFrame(server) == Data("ping".utf8))
    try IPCSocket.writeFrame(server, Data("pong".utf8))
    #expect(try IPCSocket.readFrame(client) == Data("pong".utf8))
  }

  @Test
  func readingFromAClosedPeerReportsClosed() throws {
    var descriptors: [Int32] = [0, 0]
    #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0)
    defer { close(descriptors[0]) }
    close(descriptors[1])

    #expect(throws: IPCError.closed) { try IPCSocket.readFrame(descriptors[0]) }
  }

  @Test
  func aSilentPeerTimesOut() throws {
    var descriptors: [Int32] = [0, 0]
    #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0)
    defer {
      close(descriptors[0])
      close(descriptors[1])
    }
    IPCSocket.setTimeout(descriptors[0], seconds: 1)

    #expect(throws: IPCError.timedOut) { try IPCSocket.readFrame(descriptors[0]) }
  }

  @Test
  func aSecondListenerOnTheSamePathDefersToTheFirst() throws {
    let path = "\(directory)/s.sock"
    let first = try #require(try IPCListener.bind(path: path, backlog: 1))

    #expect(try IPCListener.bind(path: path, backlog: 1) == nil)
    withExtendedLifetime(first) {
      #expect(FileManager.default.fileExists(atPath: path))
    }
  }

  @Test
  func releasingAListenerRemovesItsSocket() throws {
    let path = "\(directory)/s.sock"
    _ = try #require(try IPCListener.bind(path: path, backlog: 1))

    #expect(!FileManager.default.fileExists(atPath: path))
    #expect(try IPCSocket.connect(path: path, timeoutSeconds: 1) == nil)
  }

  @Test
  func aPathLongerThanSockaddrIsRefused() {
    let path = "/tmp/" + String(repeating: "x", count: IPCSocket.pathCapacity)

    #expect(throws: IPCError.pathTooLong(path: path, limit: IPCSocket.pathCapacity)) { try IPCSocket.connect(path: path, timeoutSeconds: 1) }
    #expect(throws: (any Error).self) { try IPCListener.bind(path: path, backlog: 1) }
  }

  @Test
  func aPrivateDirectoryIsCreatedTightenedAndRefusedWhenNotOwnedOrLinked() throws {
    let owned = "\(directory)/owned"
    try IPCSocket.requirePrivateDirectory(owned, creating: true)
    chmod(owned, 0o777)
    #expect(throws: IPCError.sharedDirectory(path: owned)) { try IPCSocket.requirePrivateDirectory(owned, creating: false) }
    try IPCSocket.requirePrivateDirectory(owned, creating: true)
    let attributes = try FileManager.default.attributesOfItem(atPath: owned)
    #expect(attributes[.posixPermissions] as? Int == IPCSocket.ownerOnlyPermissions)

    let linked = "\(directory)/linked"
    #expect(symlink(owned, linked) == 0)
    #expect(throws: IPCError.sharedDirectory(path: linked)) { try IPCSocket.requirePrivateDirectory(linked, creating: true) }
    #expect(throws: Never.self) { try IPCSocket.requirePrivateDirectory("\(directory)/absent", creating: false) }
  }

  @Test
  func preparedDirectoriesAreOwnerOnly() throws {
    let loose = "\(directory)/loose"
    #expect(mkdir(loose, 0o777) == 0)
    try IPCSocket.prepareDirectory(loose)

    let mode = try FileManager.default.attributesOfItem(atPath: loose)[.posixPermissions] as? Int
    #expect(mode == IPCSocket.ownerOnlyPermissions)
  }
}

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
import os

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
  func aClientThatSeesTheSocketAppearIsNeverRefused() throws {
    let refusals = OSAllocatedUnfairLock(initialState: 0)
    for attempt in 0..<200 {
      let path = "\(directory)/r\(attempt).sock"
      let finished = DispatchSemaphore(value: 0)
      Thread.detachNewThread {
        defer { finished.signal() }
        // A client woken by the directory changing connects as soon as the socket's name exists.
        let deadline = Date().addingTimeInterval(5)
        while access(path, F_OK) != 0 {
          guard Date() < deadline else { return }
        }
        if Self.rawConnect(path) == ECONNREFUSED {
          refusals.withLock { $0 += 1 }
        }
      }
      let listener = try #require(try IPCListener.bind(path: path, backlog: 1))
      finished.wait()
      withExtendedLifetime(listener) {}
    }

    #expect(refusals.withLock { $0 } == 0)
  }

  /// The errno of a connect to `path`, or 0 when it connects.
  private static func rawConnect(_ path: String) -> Int32 {
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    defer { close(descriptor) }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &address.sun_path) { buffer in
      let bytes = Array(path.utf8.prefix(buffer.count - 1))
      buffer.copyBytes(from: bytes)
      buffer[bytes.count] = 0
    }
    let result = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    return result == 0 ? 0 : errno
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

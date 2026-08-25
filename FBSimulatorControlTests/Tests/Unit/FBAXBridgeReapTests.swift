/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
import FBControlCore
@testable import FBSimulatorControl
import Foundation
import XCTest

/// Reaping bridge guests that no host is connected to.
///
/// Driven against real listening Unix sockets rather than a mock, because the property under test is a
/// property of the socket: that a guest already serving a client never accepts a second one, which is
/// what makes "it answered" mean "nobody else has it".
final class FBAXBridgeReapTests: XCTestCase {

  private var directory = ""

  override func setUpWithError() throws {
    // Under /tmp with short names on purpose: `sun_path` is 104 bytes, and the per-user temp directory
    // alone is ~50 of them, so a UUID-named socket beneath it cannot be bound at all.
    directory = "/tmp/axr-\(UInt32.random(in: 0..<0xffff_ffff))"
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(atPath: directory)
  }

  private func socketPath(_ name: String = String(UInt32.random(in: 0..<0xffff_ffff))) -> String {
    "\(directory)/\(FBAXBridgeSocket.prefix)\(name)\(FBAXBridgeSocket.suffix)"
  }

  /// A listener that answers one shutdown probe the way the guest does, then stops.
  @discardableResult
  private func startFakeGuest(
    at path: String,
    answering: Bool,
    backlog: Int32 = 4,
    reply: String = #"{"ok":true,"shutdown":true}"#
  ) throws -> Int32 {
    let listener = socket(AF_UNIX, SOCK_STREAM, 0)
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    _ = withUnsafeMutablePointer(to: &address.sun_path) { raw in
      path.withCString { strcpy(UnsafeMutableRawPointer(raw).assumingMemoryBound(to: CChar.self), $0) }
    }
    let bound = withUnsafePointer(to: &address) { raw in
      raw.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
      }
    }
    XCTAssertTrue(bound, "failed to bind \(path)")
    XCTAssertEqual(listen(listener, backlog), 0)
    guard answering else {
      // Bound and listening but never accepting — the shape of a guest already serving somebody.
      return listener
    }
    DispatchQueue.global().async {
      let connection = accept(listener, nil, nil)
      guard connection >= 0 else { return }
      var header = [UInt8](repeating: 0, count: 4)
      _ = recv(connection, &header, 4, MSG_WAITALL)
      let length = (Int(header[0]) << 24) | (Int(header[1]) << 16) | (Int(header[2]) << 8) | Int(header[3])
      var body = [UInt8](repeating: 0, count: max(length, 1))
      _ = recv(connection, &body, length, MSG_WAITALL)
      let payload = Array(reply.utf8)
      var out: [UInt8] = [
        UInt8((payload.count >> 24) & 0xff), UInt8((payload.count >> 16) & 0xff),
        UInt8((payload.count >> 8) & 0xff), UInt8(payload.count & 0xff),
      ]
      out.append(contentsOf: payload)
      _ = send(connection, out, out.count, 0)
      close(connection)
      close(listener)
    }
    return listener
  }

  /// Occupies `count` slots of a listener's accept queue and keeps them open, the way another host
  /// holding a connection does. Returns the client descriptors so the caller can close them.
  private func occupyBacklog(at path: String, count: Int) -> [Int32] {
    var clients: [Int32] = []
    for _ in 0..<count {
      let client = socket(AF_UNIX, SOCK_STREAM, 0)
      guard client >= 0 else { continue }
      var address = sockaddr_un()
      address.sun_family = sa_family_t(AF_UNIX)
      _ = withUnsafeMutablePointer(to: &address.sun_path) { raw in
        path.withCString { strcpy(UnsafeMutableRawPointer(raw).assumingMemoryBound(to: CChar.self), $0) }
      }
      let connected = withUnsafePointer(to: &address) { raw in
        raw.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          Darwin.connect(client, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
        }
      }
      if connected {
        clients.append(client)
      } else {
        close(client)
      }
    }
    return clients
  }

  // A refused connection is what the reaper reads as "the guest has gone", and on BSD a full accept queue
  // is refused with the same errno as nothing being bound. The serve loop handles one client at a time,
  // so a second host sits in the queue — and the backlog is what decides whether the probe after it is
  // queued or refused. With room, a live guest is correctly reported busy and keeps its socket.
  //
  // Sized off the guest's real backlog rather than a number chosen here, so this tracks the guest: if the
  // backlog is ever reduced to one again, this fails rather than quietly going back to deleting a live
  // guest's socket.
  func testALiveGuestWithAClientQueuedKeepsItsSocket() throws {
    let path = socketPath()
    let listener = try startFakeGuest(at: path, answering: false, backlog: FBAXBridgeSocket.guestListenBacklog)
    defer { close(listener) }
    let clients = occupyBacklog(at: path, count: 1)
    defer { clients.forEach { close($0) } }

    let summary = FBAXBridgeReap.reapIdleGuests(inDirectory: directory, probeTimeout: 1)

    XCTAssertEqual(summary.busy, [path])
    XCTAssertTrue(summary.removedStaleSockets.isEmpty, "a live guest's socket must survive the reap")
    XCTAssertTrue(FileManager.default.fileExists(atPath: path))
  }

  func testAGuestThatAnswersIsReaped() throws {
    let path = socketPath()
    try startFakeGuest(at: path, answering: true)

    let summary = FBAXBridgeReap.reapIdleGuests(inDirectory: directory, probeTimeout: 3)

    XCTAssertEqual(summary.shutDown, [path])
    XCTAssertTrue(summary.busy.isEmpty)
    XCTAssertTrue(summary.removedStaleSockets.isEmpty)
  }

  // The property the whole design rests on: a guest that already has a client never accepts the probe,
  // so it is left alone. Getting this wrong would take a bridge out from under a running session.
  func testAGuestWithAClientIsLeftAlone() throws {
    let path = socketPath()
    let listener = try startFakeGuest(at: path, answering: false)
    defer { close(listener) }

    let summary = FBAXBridgeReap.reapIdleGuests(inDirectory: directory, probeTimeout: 1)

    XCTAssertEqual(summary.busy, [path])
    XCTAssertTrue(summary.shutDown.isEmpty)
    XCTAssertTrue(summary.removedStaleSockets.isEmpty, "a busy guest's socket must survive the reap")
    XCTAssertTrue(FileManager.default.fileExists(atPath: path))
  }

  // Observed against a real orphan: a guest built before the verb existed answers with an error. It
  // answered, so it is provably idle — calling it busy would send someone hunting a client that is not
  // there. It still cannot be collected, and the summary says exactly that.
  func testAnOlderGuestThatRejectsTheVerbIsReportedUnreapable() throws {
    let path = socketPath()
    try startFakeGuest(
      at: path,
      answering: true,
      reply: #"{"ok":false,"error":"unsupported verb: shutdown","error_kind":"bad_request"}"#
    )

    let summary = FBAXBridgeReap.reapIdleGuests(inDirectory: directory, probeTimeout: 3)

    XCTAssertEqual(summary.unreapable, [path])
    XCTAssertTrue(summary.busy.isEmpty, "an idle guest must not be reported as busy")
    XCTAssertTrue(summary.shutDown.isEmpty)
    XCTAssertTrue(FileManager.default.fileExists(atPath: path), "its socket is still live and must survive")
  }

  func testAStaleSocketFileIsRemoved() throws {
    let path = socketPath()
    FileManager.default.createFile(atPath: path, contents: Data())

    let summary = FBAXBridgeReap.reapIdleGuests(inDirectory: directory, probeTimeout: 1)

    XCTAssertEqual(summary.removedStaleSockets, [path])
    XCTAssertFalse(FileManager.default.fileExists(atPath: path))
  }

  // A reap must not touch anything that is not ours, however tempting the directory looks.
  func testUnrelatedFilesAreUntouched() throws {
    let unrelated = "\(directory)/something-else.sock"
    FileManager.default.createFile(atPath: unrelated, contents: Data())

    let summary = FBAXBridgeReap.reapIdleGuests(inDirectory: directory, probeTimeout: 1)

    XCTAssertTrue(summary.isEmpty)
    XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated))
  }

  // The transport and the reaper must agree on what a bridge socket is called, or the reaper collects
  // nothing and says so cheerfully.
  func testTheTransportNamingIsRecognisedByTheReaper() {
    let path = FBAXBridgeSocket.path(forConnection: "ABC")
    XCTAssertEqual(path, "/tmp/idb_axbridge_ABC.sock")
    XCTAssertTrue(path.hasPrefix("\(FBAXBridgeSocket.directory)/\(FBAXBridgeSocket.prefix)"))
    XCTAssertTrue(path.hasSuffix(FBAXBridgeSocket.suffix))
  }

  // Where the sockets live, which is a security property rather than a naming one: the reaper probes
  // and unlinks the paths it finds there, and a predictable socket name in a directory anyone can write
  // to can be bound by somebody else first.
  func testTheSocketDirectoryIsPrivateToThisUser() throws {
    // `realpath` rather than `resolvingSymlinksInPath`, which deliberately leaves `/tmp` alone: on
    // macOS that is a 0755 symlink to the 1777 directory actually holding the sockets, and it is the
    // latter's mode that decides who can write there.
    let resolved = try XCTUnwrap(resolvingSymlinks(FBAXBridgeSocket.directory))
    let attributes = try FileManager.default.attributesOfItem(atPath: resolved)
    let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).uint16Value
    // BUG: the guests live in a world-writable directory shared with every other process on the
    // machine — flipped in the following commit. The mask is other-write alone, matching the claim:
    // group-write would be a different and lesser problem.
    XCTAssertNotEqual(
      permissions & 0o002, 0,
      "dir=\(FBAXBridgeSocket.directory) resolved=\(resolved) mode=\(String(permissions, radix: 8))")
  }

  private func resolvingSymlinks(_ path: String) -> String? {
    guard let resolved = realpath(path, nil) else {
      return nil
    }
    defer { free(resolved) }
    return String(cString: resolved)
  }

  // A bridge socket is recognised by a filename prefix because it shares a directory with unrelated
  // files. Moving to a directory of our own is what removes the need for the prefix — and it has to be
  // removed, because `sun_path` cannot afford both.
  func testABridgeSocketIsRecognisedByItsFilename() {
    // BUG: the directory is shared, so the prefix is load-bearing — flipped in the following commit.
    XCTAssertFalse(FBAXBridgeSocket.prefix.isEmpty)
    let occupied =
      FBAXBridgeSocket.directory.count + FBAXBridgeSocket.prefix.count
      + UUID().uuidString.count + FBAXBridgeSocket.suffix.count + 1
    XCTAssertLessThan(occupied, 104, "a bridge socket path must fit in sun_path")
  }
}

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
    "\(directory)/\(name)\(FBAXBridgeSocket.suffix)"
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

  // A reap must not touch anything that is not ours. What answers "is it ours" is now the directory —
  // we own it and put nothing else in it — so a filename no longer has to prove anything. The suffix
  // is still checked, and is what keeps a reap off a file that is not a socket at all.
  func testFilesThatAreNotSocketsAreUntouched() throws {
    let unrelated = "\(directory)/something-else.txt"
    FileManager.default.createFile(atPath: unrelated, contents: Data())

    let summary = FBAXBridgeReap.reapIdleGuests(inDirectory: directory, probeTimeout: 1)

    XCTAssertTrue(summary.isEmpty)
    XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated))
  }

  // The transport and the reaper must agree on what a bridge socket is called, or the reaper collects
  // nothing and says so cheerfully.
  func testTheTransportNamingIsRecognisedByTheReaper() {
    let path = FBAXBridgeSocket.path(forConnection: "ABC")
    XCTAssertEqual(path, "\(FBAXBridgeSocket.directory)/ABC.sock")
    XCTAssertTrue(path.hasSuffix(FBAXBridgeSocket.suffix))
  }

  // Where the sockets live, which is a security property rather than a naming one: the reaper probes
  // and unlinks the paths it finds there, and a predictable socket name in a directory anyone can write
  // to can be bound by somebody else first.
  func testTheSocketDirectoryIsPrivateToThisUser() throws {
    try FBAXBridgeSocket.prepareDirectory()
    // `realpath` rather than `resolvingSymlinksInPath`, which deliberately leaves `/tmp` alone: on
    // macOS that is a 0755 symlink to the 1777 directory that used to hold the sockets, and it is the
    // latter's mode that decides who can write there.
    let resolved = try XCTUnwrap(resolvingSymlinks(FBAXBridgeSocket.directory))
    let attributes = try FileManager.default.attributesOfItem(atPath: resolved)
    let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).uint16Value
    XCTAssertEqual(
      permissions & 0o077, 0,
      "dir=\(FBAXBridgeSocket.directory) resolved=\(resolved) mode=\(String(permissions, radix: 8))")
  }

  // A directory that is already there must still come out owner-only. `createDirectory` applies its
  // attributes only when it creates something, so on the `/tmp` fallback another local user could
  // pre-create `idb-ax` with a permissive mode and we would bind predictable socket names into it.
  func testPreparingAnExistingLooseDirectoryTightensIt() throws {
    let loose = "\(directory)/loose-idb-ax"
    try FileManager.default.createDirectory(
      atPath: loose, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o777])
    try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: loose)
    XCTAssertEqual(try mode(of: loose), 0o777, "precondition: the directory starts world-writable")

    try FBAXBridgeSocket.prepareDirectory(loose)

    let tightened = try mode(of: loose)
    XCTAssertEqual(tightened & 0o077, 0, "mode=\(String(tightened, radix: 8))")
  }

  private func mode(of path: String) throws -> UInt16 {
    let attributes = try FileManager.default.attributesOfItem(atPath: path)
    return try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).uint16Value
  }

  // The directory has to be there before a spawn, because the guest binds into it and `bind` does not
  // create intermediate directories. Asking twice must be fine — every spawn asks.
  func testPreparingTheSocketDirectoryIsRepeatable() throws {
    try FBAXBridgeSocket.prepareDirectory()
    try FBAXBridgeSocket.prepareDirectory()
    var isDirectory: ObjCBool = false
    XCTAssertTrue(FileManager.default.fileExists(atPath: FBAXBridgeSocket.directory, isDirectory: &isDirectory))
    XCTAssertTrue(isDirectory.boolValue)
  }

  private func resolvingSymlinks(_ path: String) -> String? {
    guard let resolved = realpath(path, nil) else {
      return nil
    }
    defer { free(resolved) }
    return String(cString: resolved)
  }

  // Owning the directory is what pays for the name: no filename prefix is needed to tell our sockets
  // apart from anyone else's, and `sun_path` could not have afforded a subdirectory and a prefix both.
  //
  // The headroom is small — six bytes on a stock layout — and over-running it is worse than an error,
  // because `bind` truncates silently rather than failing, which would land two simulators on one
  // socket. So this asserts the budget rather than trusting it.
  func testABridgeSocketPathFitsInSunPath() {
    let path = FBAXBridgeSocket.path(forConnection: UUID().uuidString)
    XCTAssertLessThan(path.utf8.count, 104, "\(path) is \(path.utf8.count) bytes")
  }

  // What a caller is told when a socket path will not fit in `sun_path`. It cannot be connected to at
  // all, so the only question is whether the message says why — and the budget is tight enough (six
  // bytes) that somebody will eventually hit this.
  func testAnOverLongSocketPathIsRejectedForItsLength() async throws {
    let tooLong = "\(directory)/\(String(repeating: "x", count: 120)).sock"
    XCTAssertGreaterThan(tooLong.utf8.count, 103)
    do {
      _ = try await FBAXBridgeConnection.connect(path: tooLong, timeout: 1)
      XCTFail("connecting to a path that cannot fit in sun_path must not succeed")
    } catch {
      let message = error.localizedDescription
      XCTAssertTrue(message.contains("sockaddr_un limit"), message)
      XCTAssertTrue(message.contains("\(FBAXBridgeConnection.sunPathCapacity)"), message)
      XCTAssertFalse(message.contains("timed out connecting"), message)
    }
  }

  // Rejection must not cost the caller the connect deadline.
  func testAnOverLongSocketPathIsRejectedWithoutWaiting() async throws {
    let tooLong = "\(directory)/\(String(repeating: "x", count: 120)).sock"
    let started = Date()
    _ = try? await FBAXBridgeConnection.connect(path: tooLong, timeout: 10)
    XCTAssertLessThan(Date().timeIntervalSince(started), 1)
  }

  // The kernel reads an all-zero `timeval` as no deadline at all rather than as an immediate one, so a
  // deadline that rounds to zero removes the bound instead of shortening it.

  func testAWholeSecondDeadlineConvertsExactly() {
    let window = FBAXBridgePersistentTransport.receiveWindow(2)
    XCTAssertEqual(window.tv_sec, 2)
    XCTAssertEqual(window.tv_usec, 0)
  }

  func testASubSecondDeadlineIsKept() {
    let window = FBAXBridgePersistentTransport.receiveWindow(0.1)
    XCTAssertEqual(window.tv_sec, 0)
    XCTAssertEqual(window.tv_usec, 100_000)
  }

  func testAFractionalDeadlineKeepsItsFraction() {
    let window = FBAXBridgePersistentTransport.receiveWindow(1.5)
    XCTAssertEqual(window.tv_sec, 1)
    XCTAssertEqual(window.tv_usec, 500_000)
  }

  // Zero is the one deadline the conversion already gets right, and it has to stay that way: the kernel
  // reads an all-zero `timeval` as no deadline, so it must only ever come from a caller asking for none.
  func testAZeroDeadlineStaysZero() {
    let window = FBAXBridgePersistentTransport.receiveWindow(0)
    XCTAssertEqual(window.tv_sec, 0)
    XCTAssertEqual(window.tv_usec, 0)
  }

  func testTheSunPathCapacityMatchesThePlatform() {
    XCTAssertEqual(FBAXBridgeConnection.sunPathCapacity, 104)
  }

  func testASpawnNamesTheIdleTimeoutItWants() {
    let arguments = FBAXBridgePersistentTransport.serveArguments(socketPath: "/x/y.sock")
    XCTAssertEqual(
      arguments,
      ["accessibility", "serve", "/x/y.sock", "--idle-timeout", "\(FBAXBridgePersistentTransport.idleTimeoutSeconds)"])
  }

  func testASpawnCanAskForADifferentIdleTimeout() {
    let arguments = FBAXBridgePersistentTransport.serveArguments(socketPath: "/x/y.sock", idleTimeoutSeconds: 7)
    XCTAssertEqual(arguments, ["accessibility", "serve", "/x/y.sock", "--idle-timeout", "7"])
  }

  // Two processes have to arrive at the same name independently.

  func testTheSocketForASimulatorIsTheSameForEveryProcessThatAsks() {
    let udid = "AE4DEFD9-F94B-4543-84F1-849D4B5C4351"
    XCTAssertEqual(FBAXBridgeSocket.path(forSimulator: udid), FBAXBridgeSocket.path(forSimulator: udid))
  }

  // A UDID is hex and can reach two callers in different cases; both must land on one socket.
  func testTheSocketForASimulatorIgnoresUdidCase() {
    let upper = FBAXBridgeSocket.path(forSimulator: "AE4DEFD9-F94B-4543-84F1-849D4B5C4351")
    let lower = FBAXBridgeSocket.path(forSimulator: "ae4defd9-f94b-4543-84f1-849d4b5c4351")
    XCTAssertEqual(upper, lower)
  }

  func testDifferentSimulatorsGetDifferentSockets() {
    let first = FBAXBridgeSocket.path(forSimulator: "AE4DEFD9-F94B-4543-84F1-849D4B5C4351")
    let second = FBAXBridgeSocket.path(forSimulator: "7A44631A-36A9-4575-ADDA-2477A4719519")
    XCTAssertNotEqual(first, second)
  }

  func testASimulatorSocketIsRecognisedByTheReaper() {
    let path = FBAXBridgeSocket.path(forSimulator: "AE4DEFD9-F94B-4543-84F1-849D4B5C4351")
    XCTAssertEqual(path, "\(FBAXBridgeSocket.directory)/AE4DEFD9F94B454384F1849D4B5C4351.sock")
    XCTAssertTrue(path.hasSuffix(FBAXBridgeSocket.suffix))
  }

  // Only the adopted case is reachable without building an `FBSubprocess`, which needs three futures
  // and a spawn configuration. The started-shared and started-private cases are covered end to end,
  // where the difference shows as a guest that outlives its companion or does not.
  func testAnAdoptedGuestIsNeverReapedByTheHostUsingIt() {
    XCTAssertFalse(FBAXBridgeGuestOwnership.shared(nil).reapsGuestOnRelease)
    XCTAssertNil(FBAXBridgeGuestOwnership.shared(nil).process)
  }

  // `bind` truncates rather than failing, so the margin is checked against the real limit.
  func testASimulatorSocketPathFitsInSunPath() {
    let path = FBAXBridgeSocket.path(forSimulator: "AE4DEFD9-F94B-4543-84F1-849D4B5C4351")
    XCTAssertLessThan(
      path.utf8.count, FBAXBridgeConnection.sunPathCapacity, "\(path) is \(path.utf8.count) bytes")
  }
}

/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
import FBAXCore
import FBControlCore
@testable import FBSimulatorControl
import Foundation
import SimulatorIPC
import XCTest
import os

/// Bridge socket naming and location, the deadlines a host reaches one with, and the spawn arguments
/// and backend names that decide which guest it gets.
final class AXBridgeSocketTests: XCTestCase {

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

  // The adoption deadline is sub-second, so the conversion has to keep fractions.
  func testTheAdoptionDeadlineIsSubSecondAndNonZero() {
    let window = SimulatorFrameworkBridgePersistentTransport.receiveWindow(SimulatorFrameworkBridgePersistentTransport.adoptionTimeout)
    XCTAssertLessThan(SimulatorFrameworkBridgePersistentTransport.adoptionTimeout, 1)
    XCTAssertGreaterThan(window.tv_usec, 0, "a sub-second deadline that converts to zero is no deadline")
  }
  func testEveryResolvedBackendNameRoundTrips() {
    let cases: [(AXBridgePersistence, UIAutomationBackendName)] = [
      (.oneShot, .axBridgeOneShot), (.shared, .axBridgePersistent), (.exclusive, .axBridgeExclusive),
    ]
    for (persistence, name) in cases {
      let backend = UIAutomationBackend.axBridge(
        persistence: persistence, frontmostMethod: .windowServer, automationMode: true)
      XCTAssertEqual(backend.name, name)
      XCTAssertEqual(UIAutomationBackend(resolvedName: name), backend)
    }
  }

  func testTheOneShotCaseHasAnExplicitWireName() {
    XCTAssertEqual(UIAutomationBackendName.axBridgeOneShot.rawValue, "axbridge-oneshot")
  }

  func testTheSharedCaseKeepsTheExistingWireName() {
    XCTAssertEqual(UIAutomationBackendName.axBridgePersistent.rawValue, "axbridge-persistent")
  }

  func testTheExclusiveCaseHasItsOwnWireName() {
    XCTAssertEqual(UIAutomationBackendName.axBridgeExclusive.rawValue, "axbridge-exclusive")
  }

  func testAConnectionSocketIsNamedForItsIdentifier() {
    let path = SimulatorFrameworkBridgeSocket.path(forConnection: "ABC")
    XCTAssertEqual(path, "\(SimulatorFrameworkBridgeSocket.directory)/ABC.sock")
    XCTAssertTrue(path.hasSuffix(SimulatorFrameworkBridgeSocket.suffix))
  }

  // A predictable socket name in a world-writable directory can be bound by somebody else first.
  func testTheSocketDirectoryIsPrivateToThisUser() throws {
    try SimulatorFrameworkBridgeSocket.prepareDirectory()
    // `realpath` rather than `resolvingSymlinksInPath`, which deliberately leaves `/tmp` alone: on
    // macOS that is a 0755 symlink to the 1777 directory that used to hold the sockets, and it is the
    // latter's mode that decides who can write there.
    let resolved = try XCTUnwrap(resolvingSymlinks(SimulatorFrameworkBridgeSocket.directory))
    let attributes = try FileManager.default.attributesOfItem(atPath: resolved)
    let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).uint16Value
    XCTAssertEqual(
      permissions & 0o077, 0,
      "dir=\(SimulatorFrameworkBridgeSocket.directory) resolved=\(resolved) mode=\(String(permissions, radix: 8))")
  }

  // `createDirectory` applies its attributes only when it creates something, so on the `/tmp` fallback another
  // local user could pre-create `idb-ax` with a permissive mode.
  func testPreparingAnExistingLooseDirectoryTightensIt() throws {
    let loose = "\(directory)/loose-idb-ax"
    try FileManager.default.createDirectory(
      atPath: loose, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o777])
    try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: loose)
    XCTAssertEqual(try mode(of: loose), 0o777, "precondition: the directory starts world-writable")

    try SimulatorFrameworkBridgeSocket.prepareDirectory(loose)

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
    try SimulatorFrameworkBridgeSocket.prepareDirectory()
    try SimulatorFrameworkBridgeSocket.prepareDirectory()
    var isDirectory: ObjCBool = false
    XCTAssertTrue(FileManager.default.fileExists(atPath: SimulatorFrameworkBridgeSocket.directory, isDirectory: &isDirectory))
    XCTAssertTrue(isDirectory.boolValue)
  }

  private func resolvingSymlinks(_ path: String) -> String? {
    guard let resolved = realpath(path, nil) else {
      return nil
    }
    defer { free(resolved) }
    return String(cString: resolved)
  }

  // `bind` truncates an over-long `sun_path` silently rather than failing, which would land two simulators on
  // one socket; the headroom is about six bytes on a stock layout.
  func testABridgeSocketPathFitsInSunPath() {
    let path = SimulatorFrameworkBridgeSocket.path(forConnection: UUID().uuidString)
    XCTAssertLessThan(path.utf8.count, 104, "\(path) is \(path.utf8.count) bytes")
  }

  // A path that will not fit in `sun_path` cannot be connected to at all, so the message must say why.
  func testAnOverLongSocketPathIsRejectedForItsLength() async throws {
    let tooLong = "\(directory)/\(String(repeating: "x", count: 120)).sock"
    XCTAssertGreaterThan(tooLong.utf8.count, 103)
    do {
      _ = try await SimulatorFrameworkBridgeConnection.connect(path: tooLong, timeout: 1)
      XCTFail("connecting to a path that cannot fit in sun_path must not succeed")
    } catch {
      let message = error.localizedDescription
      XCTAssertTrue(message.contains("sockaddr_un limit"), message)
      XCTAssertTrue(message.contains("\(IPCSocket.pathCapacity)"), message)
      XCTAssertFalse(message.contains("timed out connecting"), message)
    }
  }

  // Rejection must not cost the caller the connect deadline.
  func testAnOverLongSocketPathIsRejectedWithoutWaiting() async throws {
    let tooLong = "\(directory)/\(String(repeating: "x", count: 120)).sock"
    let started = Date()
    _ = try? await SimulatorFrameworkBridgeConnection.connect(path: tooLong, timeout: 10)
    XCTAssertLessThan(Date().timeIntervalSince(started), 1)
  }

  // A guest whose process is already gone, signalled before it could bind.
  private func exitedGuest(signal: Int32) async throws -> RunningSubprocess {
    let guest = try await Subprocess(executable: "/bin/sh", arguments: ["-c", "kill -\(signal) $$"])
      .launch(output: .closed, error: .closed)
    _ = try await guest.terminationStatus
    return guest
  }

  private func normallyExitedGuest(code: Int32) async throws -> RunningSubprocess {
    let guest = try await Subprocess(executable: "/bin/sh", arguments: ["-c", "exit \(code)"])
      .launch(output: .closed, error: .closed)
    _ = try await guest.terminationStatus
    return guest
  }

  func testSharedLockLoserWaitsForTheWinnerWithoutHidingFailedStartups() async throws {
    var pair: [Int32] = [-1, -1]
    XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &pair), 0)
    let descriptor = pair[0]
    defer {
      close(pair[0])
      close(pair[1])
    }
    let cases: [(BridgeServiceScope, RunningSubprocess, Int?, Int?)] = [
      (.shared, try await normallyExitedGuest(code: 0), nil, nil),
      (.exclusive, try await normallyExitedGuest(code: 0), 0, nil),
      (.shared, try await normallyExitedGuest(code: 3), 3, nil),
      (.shared, try await exitedGuest(signal: SIGABRT), nil, Int(SIGABRT)),
    ]
    for (scope, guest, exitCode, signal) in cases {
      let attempts = OSAllocatedUnfairLock(initialState: 0)
      do {
        let connected = try await SimulatorFrameworkBridgeConnection.connect(
          path: "\(directory)/contended.sock", timeout: 2, guest: guest, scope: scope,
          attempt: { _ in
            attempts.withLock { count in
              count += 1
              return count >= 3 ? descriptor : nil
            }
          })
        XCTAssertNil(exitCode, "\(scope)")
        XCTAssertNil(signal, "\(scope)")
        XCTAssertEqual(connected, descriptor, "\(scope)")
        XCTAssertEqual(attempts.withLock { $0 }, 3, "\(scope)")
      } catch let error as AXBridgeError {
        guard case let .guestDiedBeforeBinding(pid, actualSignal, actualCode, _) = error else {
          return XCTFail("unexpected connection error: \(error)")
        }
        XCTAssertTrue(exitCode != nil || signal != nil, "\(scope)")
        XCTAssertEqual(pid, guest.processIdentifier)
        XCTAssertEqual(actualCode, exitCode, "\(scope)")
        XCTAssertEqual(actualSignal, signal, "\(scope)")
        XCTAssertEqual(attempts.withLock { $0 }, 2, "\(scope)")
      }
    }
  }

  // The death check runs after the connect attempt, so a guest that bound before dying still yields its descriptor.
  func testAConnectThatSucceedsWinsOverAGuestKnownToBeDead() async throws {
    let bound = "\(directory)/live.sock"
    let listener = socket(AF_UNIX, SOCK_STREAM, 0)
    XCTAssertGreaterThanOrEqual(listener, 0)
    defer {
      close(listener)
      unlink(bound)
    }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    bound.withCString { source in
      withUnsafeMutablePointer(to: &address.sun_path) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
          _ = memcpy(destination, source, strlen(source) + 1)
        }
      }
    }
    let bindResult = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    XCTAssertEqual(bindResult, 0, "precondition: the socket binds")
    XCTAssertEqual(listen(listener, 1), 0)

    let connected = try await SimulatorFrameworkBridgeConnection.connect(
      path: bound, timeout: 2, guest: try await exitedGuest(signal: SIGABRT))
    XCTAssertGreaterThanOrEqual(connected, 0)
    close(connected)
  }

  // A guest that is already gone must cost the caller a poll, not the whole deadline.
  func testAGuestThatDiedBeforeBindingIsGivenUpOnWithoutWaiting() async throws {
    let unbound = "\(directory)/dead.sock"
    let guest = try await exitedGuest(signal: SIGABRT)
    let started = Date()
    _ = try? await SimulatorFrameworkBridgeConnection.connect(path: unbound, timeout: 2, guest: guest)
    XCTAssertLessThan(Date().timeIntervalSince(started), 1)
  }

  // The signal that killed the guest is known by the time the connect gives up, so the failure must
  // name it rather than read as a timeout.
  func testAGuestThatDiedBeforeBindingIsReportedWithItsSignal() async throws {
    let unbound = "\(directory)/dead.sock"
    let guest = try await exitedGuest(signal: SIGABRT)
    do {
      _ = try await SimulatorFrameworkBridgeConnection.connect(path: unbound, timeout: 1, guest: guest)
      XCTFail("connecting to a socket no guest will ever bind must not succeed")
    } catch let error as AXBridgeError {
      guard case let .guestDiedBeforeBinding(pid, signal, exitCode, _) = error else {
        return XCTFail("expected guestDiedBeforeBinding, got \(error)")
      }
      XCTAssertEqual(pid, guest.processIdentifier)
      XCTAssertEqual(signal, Int(SIGABRT))
      XCTAssertNil(exitCode)
      let message = error.localizedDescription
      XCTAssertFalse(message.contains("timed out connecting"), message)
      XCTAssertTrue(message.contains("signal \(SIGABRT)"), message)
      XCTAssertTrue(message.contains("\(guest.processIdentifier)"), message)
    }
  }

  // MARK: - Decoding the guest's exit

  // A signal and an exit code must not be read as each other.
  func testASignalledStatusDecodesToItsSignal() {
    let cause = SimulatorFrameworkBridgeConnection.terminationCause(.signalled(SIGABRT))
    XCTAssertEqual(cause.signal, Int(SIGABRT))
    XCTAssertNil(cause.exitCode)
  }

  func testAnExitedStatusDecodesToItsCode() {
    let cause = SimulatorFrameworkBridgeConnection.terminationCause(.exited(3))
    XCTAssertEqual(cause.exitCode, 3)
    XCTAssertNil(cause.signal)
  }

  // No status is not the same as a zero status, which would read as a clean exit the guest never made.
  func testAMissingStatusDecodesToNeither() {
    let cause = SimulatorFrameworkBridgeConnection.terminationCause(nil)
    XCTAssertNil(cause.signal)
    XCTAssertNil(cause.exitCode)
    let error = AXBridgeError.guestDiedBeforeBinding(
      pid: 4242, signal: cause.signal, exitCode: cause.exitCode, path: "/x/y.sock")
    XCTAssertTrue(error.localizedDescription.contains("no exit status recorded"), error.localizedDescription)
  }

  // Signal zero is not a signal, and the message must not claim one was raised.
  func testAZeroSignalIsNotReportedAsASignal() {
    let error = AXBridgeError.guestDiedBeforeBinding(pid: 4242, signal: 0, exitCode: nil, path: "/x/y.sock")
    XCTAssertFalse(error.localizedDescription.contains("signal 0"), error.localizedDescription)
  }

  // The kernel reads an all-zero `timeval` as no deadline at all rather than as an immediate one, so a
  // deadline that rounds to zero removes the bound instead of shortening it.

  func testAWholeSecondDeadlineConvertsExactly() {
    let window = SimulatorFrameworkBridgePersistentTransport.receiveWindow(2)
    XCTAssertEqual(window.tv_sec, 2)
    XCTAssertEqual(window.tv_usec, 0)
  }

  func testAFractionalDeadlineKeepsItsFraction() {
    let window = SimulatorFrameworkBridgePersistentTransport.receiveWindow(1.5)
    XCTAssertEqual(window.tv_sec, 1)
    XCTAssertEqual(window.tv_usec, 500_000)
  }

  // Zero must only ever come from a caller asking for no deadline.
  func testAZeroDeadlineStaysZero() {
    let window = SimulatorFrameworkBridgePersistentTransport.receiveWindow(0)
    XCTAssertEqual(window.tv_sec, 0)
    XCTAssertEqual(window.tv_usec, 0)
  }

  func testTheSunPathCapacityMatchesThePlatform() {
    XCTAssertEqual(IPCSocket.pathCapacity, 104)
  }

  // Nobody else can reach an exclusive guest's socket, so once its client goes there is no next one to wait for.
  func testAnExclusiveSpawnPassesExitOnDisconnect() {
    let arguments = SimulatorFrameworkBridgePersistentTransport.serveArguments(
      socketPath: "/x/y.sock", scope: .exclusive)
    XCTAssertEqual(Array(arguments.suffix(2)), ["--exit-on-disconnect", "1"])
  }

  // A shared guest must stay up for the next client, so the flag is never passed there.
  func testASharedSpawnOmitsExitOnDisconnect() {
    let arguments = SimulatorFrameworkBridgePersistentTransport.serveArguments(
      socketPath: "/x/y.sock", scope: .shared)
    XCTAssertFalse(arguments.contains("--exit-on-disconnect"))
  }

  func testASpawnPassesTheDefaultIdleTimeout() {
    let arguments = SimulatorFrameworkBridgePersistentTransport.serveArguments(socketPath: "/x/y.sock", scope: .shared)
    XCTAssertEqual(
      arguments,
      ["serve", "/x/y.sock", "--idle-timeout", "\(SimulatorFrameworkBridgePersistentTransport.idleTimeoutSeconds)"])
  }

  func testASpawnCanAskForADifferentIdleTimeout() {
    let arguments = SimulatorFrameworkBridgePersistentTransport.serveArguments(socketPath: "/x/y.sock", scope: .shared, idleTimeoutSeconds: 7)
    XCTAssertEqual(arguments, ["serve", "/x/y.sock", "--idle-timeout", "7"])
  }

  // A UDID is hex and can reach two callers in different cases; both must land on one socket.
  func testTheSocketForASimulatorIgnoresUdidCase() {
    let upper = SimulatorFrameworkBridgeSocket.path(forSimulator: "AE4DEFD9-F94B-4543-84F1-849D4B5C4351")
    let lower = SimulatorFrameworkBridgeSocket.path(forSimulator: "ae4defd9-f94b-4543-84f1-849d4b5c4351")
    XCTAssertEqual(upper, lower)
  }

  func testASimulatorSocketIsNamedForItsSimulator() {
    let path = SimulatorFrameworkBridgeSocket.path(forSimulator: "AE4DEFD9-F94B-4543-84F1-849D4B5C4351")
    XCTAssertEqual(path, "\(SimulatorFrameworkBridgeSocket.directory)/AE4DEFD9F94B454384F1849D4B5C4351.sock")
    XCTAssertTrue(path.hasSuffix(SimulatorFrameworkBridgeSocket.suffix))
  }

  // `bind` truncates rather than failing, so the margin is checked against the real limit.
  func testASimulatorSocketPathFitsInSunPath() {
    let path = SimulatorFrameworkBridgeSocket.path(forSimulator: "AE4DEFD9-F94B-4543-84F1-849D4B5C4351")
    XCTAssertLessThan(
      path.utf8.count, IPCSocket.pathCapacity, "\(path) is \(path.utf8.count) bytes")
  }

  // MARK: - Which guest a target gets

  // Picking the wrong name aborts the guest before `main`, so the mapping is pinned per family.
  func testAnAppleTVTargetGetsTheTvOSGuest() {
    XCTAssertEqual(
      SimulatorFrameworkBridgeSelection.resourceName(for: .appleTV),
      "SimulatorFrameworkBridge-tvOS")
  }

  func testEveryNonTVFamilyGetsTheIOSGuest() {
    let families: [ProductFamily] = [
      .iPhone, .iPad, .appleWatch, .mac, .unknown,
    ]
    for family in families {
      XCTAssertEqual(
        SimulatorFrameworkBridgeSelection.resourceName(for: family),
        "SimulatorFrameworkBridge-iOS", "\(family)")
    }
  }
}

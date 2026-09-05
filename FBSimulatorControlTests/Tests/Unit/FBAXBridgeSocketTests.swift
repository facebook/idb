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

/// Bridge socket naming and location, the deadlines a host reaches one with, and the spawn arguments
/// and backend names that decide which guest it gets.
final class FBAXBridgeSocketTests: XCTestCase {

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
    let window = FBAXBridgePersistentTransport.receiveWindow(FBAXBridgePersistentTransport.adoptionTimeout)
    XCTAssertLessThan(FBAXBridgePersistentTransport.adoptionTimeout, 1)
    XCTAssertGreaterThan(window.tv_usec, 0, "a sub-second deadline that converts to zero is no deadline")
  }
  func testEveryResolvedBackendNameRoundTrips() {
    let cases: [(FBAXBridgePersistence, FBUIAutomationBackendName)] = [
      (.oneShot, .axBridgeOneShot), (.shared, .axBridgePersistent), (.exclusive, .axBridgeExclusive),
    ]
    for (persistence, name) in cases {
      let backend = FBUIAutomationBackend.axBridge(
        persistence: persistence, frontmostMethod: .windowServer, automationMode: true)
      XCTAssertEqual(backend.name, name)
      XCTAssertEqual(FBUIAutomationBackend(resolvedName: name), backend)
    }
  }

  func testTheOneShotCaseHasAnExplicitWireName() {
    XCTAssertEqual(FBUIAutomationBackendName.axBridgeOneShot.rawValue, "axbridge-oneshot")
  }

  func testTheSharedCaseKeepsTheExistingWireName() {
    XCTAssertEqual(FBUIAutomationBackendName.axBridgePersistent.rawValue, "axbridge-persistent")
  }

  func testTheExclusiveCaseHasItsOwnWireName() {
    XCTAssertEqual(FBUIAutomationBackendName.axBridgeExclusive.rawValue, "axbridge-exclusive")
  }

  func testAConnectionSocketIsNamedForItsIdentifier() {
    let path = FBAXBridgeSocket.path(forConnection: "ABC")
    XCTAssertEqual(path, "\(FBAXBridgeSocket.directory)/ABC.sock")
    XCTAssertTrue(path.hasSuffix(FBAXBridgeSocket.suffix))
  }

  // A predictable socket name in a world-writable directory can be bound by somebody else first.
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

  // `createDirectory` applies its attributes only when it creates something, so on the `/tmp` fallback another
  // local user could pre-create `idb-ax` with a permissive mode.
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

  // `bind` truncates an over-long `sun_path` silently rather than failing, which would land two simulators on
  // one socket; the headroom is about six bytes on a stock layout.
  func testABridgeSocketPathFitsInSunPath() {
    let path = FBAXBridgeSocket.path(forConnection: UUID().uuidString)
    XCTAssertLessThan(path.utf8.count, 104, "\(path) is \(path.utf8.count) bytes")
  }

  // A path that will not fit in `sun_path` cannot be connected to at all, so the message must say why.
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

  // A guest whose process is already gone, signalled before it could bind.
  private func exitedGuest(pid: pid_t, signal: Int32) -> FBSubprocess<AnyObject, AnyObject, AnyObject> {
    let configuration = FBProcessSpawnConfiguration(
      launchPath: "/usr/bin/true",
      arguments: [],
      environment: [:],
      io: FBProcessIO<AnyObject, AnyObject, AnyObject>.outputToDevNull(),
      mode: .default)
    // Resolved the way `FBProcessSpawnCommandHelpers.resolveProcessFinished` resolves a signalled
    // process: `statLoc` carries the raw `waitpid` status, `signal` the number, and `exitCode` *errors*
    // rather than holding a value. A fake that leaves `exitCode` merely pending would let a reader that
    // depends on the three resolving in order pass here and fail against a real subprocess.
    let statLoc = FBMutableFuture<NSNumber>()
    statLoc.resolve(withResult: NSNumber(value: signal))
    let signalled = FBMutableFuture<NSNumber>()
    signalled.resolve(withResult: NSNumber(value: signal))
    let exitCode = FBMutableFuture<NSNumber>()
    exitCode.resolveWithError(
      FBProcessTerminationError.exitedWithSignal(
        processIdentifier: pid, processName: "SimulatorFrameworkBridge", signal: signal))
    return FBSubprocess(
      processIdentifier: pid,
      statLoc: convertFBMutableFuture(statLoc),
      exitCode: convertFBMutableFuture(exitCode),
      signal: convertFBMutableFuture(signalled),
      configuration: configuration,
      queue: DispatchQueue(label: "com.facebook.FBSimulatorControl.tests.axbridge"))
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

    let connected = try await FBAXBridgeConnection.connect(
      path: bound, timeout: 2, guest: exitedGuest(pid: 4242, signal: SIGABRT))
    XCTAssertGreaterThanOrEqual(connected, 0)
    close(connected)
  }

  // A guest that is already gone must cost the caller a poll, not the whole deadline.
  func testAGuestThatDiedBeforeBindingIsGivenUpOnWithoutWaiting() async throws {
    let unbound = "\(directory)/dead.sock"
    let guest = exitedGuest(pid: 4242, signal: SIGABRT)
    let started = Date()
    _ = try? await FBAXBridgeConnection.connect(path: unbound, timeout: 2, guest: guest)
    XCTAssertLessThan(Date().timeIntervalSince(started), 1)
  }

  // The signal that killed the guest is known by the time the connect gives up, so the failure must
  // name it rather than read as a timeout.
  func testAGuestThatDiedBeforeBindingIsReportedWithItsSignal() async throws {
    let unbound = "\(directory)/dead.sock"
    let guest = exitedGuest(pid: 4242, signal: SIGABRT)
    do {
      _ = try await FBAXBridgeConnection.connect(path: unbound, timeout: 1, guest: guest)
      XCTFail("connecting to a socket no guest will ever bind must not succeed")
    } catch let error as FBAXBridgeError {
      guard case let .guestDiedBeforeBinding(pid, signal, exitCode, _) = error else {
        return XCTFail("expected guestDiedBeforeBinding, got \(error)")
      }
      XCTAssertEqual(pid, 4242)
      XCTAssertEqual(signal, Int(SIGABRT))
      XCTAssertNil(exitCode)
      let message = error.localizedDescription
      XCTAssertFalse(message.contains("timed out connecting"), message)
      XCTAssertTrue(message.contains("signal \(SIGABRT)"), message)
      XCTAssertTrue(message.contains("4242"), message)
    }
  }

  // MARK: - Decoding the guest's exit from its waitpid status

  // The two statuses that name an outcome. A signalled process reports the signal in the low seven
  // bits; an exited one reports its code in the next byte, and the two must not be read as each other.
  func testASignalledStatusDecodesToItsSignal() {
    let cause = FBAXBridgeConnection.terminationCause(waitpidStatus: SIGABRT)
    XCTAssertEqual(cause.signal, Int(SIGABRT))
    XCTAssertNil(cause.exitCode)
  }

  func testAnExitedStatusDecodesToItsCode() {
    let cause = FBAXBridgeConnection.terminationCause(waitpidStatus: 3 << 8)
    XCTAssertEqual(cause.exitCode, 3)
    XCTAssertNil(cause.signal)
  }

  // A stopped process has not terminated, and puts its stopping signal where an exit puts its code.
  // Decoding it as an exit would report `exited with code 19` for a process that is merely paused.
  func testAStoppedStatusDecodesToNeither() {
    let stopped = (SIGSTOP << 8) | 0x7f
    let cause = FBAXBridgeConnection.terminationCause(waitpidStatus: stopped)
    XCTAssertNil(cause.signal)
    XCTAssertNil(cause.exitCode)
  }

  // No status is not the same as a zero status, which would read as a clean exit the guest never made.
  func testAMissingStatusDecodesToNeither() {
    let cause = FBAXBridgeConnection.terminationCause(waitpidStatus: nil)
    XCTAssertNil(cause.signal)
    XCTAssertNil(cause.exitCode)
    let error = FBAXBridgeError.guestDiedBeforeBinding(
      pid: 4242, signal: cause.signal, exitCode: cause.exitCode, path: "/x/y.sock")
    XCTAssertTrue(error.localizedDescription.contains("no exit status recorded"), error.localizedDescription)
  }

  // Signal zero is not a signal, and the message must not claim one was raised.
  func testAZeroSignalIsNotReportedAsASignal() {
    let error = FBAXBridgeError.guestDiedBeforeBinding(pid: 4242, signal: 0, exitCode: nil, path: "/x/y.sock")
    XCTAssertFalse(error.localizedDescription.contains("signal 0"), error.localizedDescription)
  }

  // The kernel reads an all-zero `timeval` as no deadline at all rather than as an immediate one, so a
  // deadline that rounds to zero removes the bound instead of shortening it.

  func testAWholeSecondDeadlineConvertsExactly() {
    let window = FBAXBridgePersistentTransport.receiveWindow(2)
    XCTAssertEqual(window.tv_sec, 2)
    XCTAssertEqual(window.tv_usec, 0)
  }

  func testAFractionalDeadlineKeepsItsFraction() {
    let window = FBAXBridgePersistentTransport.receiveWindow(1.5)
    XCTAssertEqual(window.tv_sec, 1)
    XCTAssertEqual(window.tv_usec, 500_000)
  }

  // Zero must only ever come from a caller asking for no deadline.
  func testAZeroDeadlineStaysZero() {
    let window = FBAXBridgePersistentTransport.receiveWindow(0)
    XCTAssertEqual(window.tv_sec, 0)
    XCTAssertEqual(window.tv_usec, 0)
  }

  func testTheSunPathCapacityMatchesThePlatform() {
    XCTAssertEqual(FBAXBridgeConnection.sunPathCapacity, 104)
  }

  // Nobody else can reach an exclusive guest's socket, so once its client goes there is no next one to wait for.
  func testAnExclusiveSpawnPassesExitOnDisconnect() {
    let arguments = FBAXBridgePersistentTransport.serveArguments(
      socketPath: "/x/y.sock", scope: .exclusive)
    XCTAssertEqual(Array(arguments.suffix(2)), ["--exit-on-disconnect", "1"])
  }

  // A shared guest must stay up for the next client, so the flag is never passed there.
  func testASharedSpawnOmitsExitOnDisconnect() {
    let arguments = FBAXBridgePersistentTransport.serveArguments(
      socketPath: "/x/y.sock", scope: .shared)
    XCTAssertFalse(arguments.contains("--exit-on-disconnect"))
  }

  func testASpawnPassesTheDefaultIdleTimeout() {
    let arguments = FBAXBridgePersistentTransport.serveArguments(socketPath: "/x/y.sock", scope: .shared)
    XCTAssertEqual(
      arguments,
      ["accessibility", "serve", "/x/y.sock", "--idle-timeout", "\(FBAXBridgePersistentTransport.idleTimeoutSeconds)"])
  }

  func testASpawnCanAskForADifferentIdleTimeout() {
    let arguments = FBAXBridgePersistentTransport.serveArguments(socketPath: "/x/y.sock", scope: .shared, idleTimeoutSeconds: 7)
    XCTAssertEqual(arguments, ["accessibility", "serve", "/x/y.sock", "--idle-timeout", "7"])
  }

  // A UDID is hex and can reach two callers in different cases; both must land on one socket.
  func testTheSocketForASimulatorIgnoresUdidCase() {
    let upper = FBAXBridgeSocket.path(forSimulator: "AE4DEFD9-F94B-4543-84F1-849D4B5C4351")
    let lower = FBAXBridgeSocket.path(forSimulator: "ae4defd9-f94b-4543-84f1-849d4b5c4351")
    XCTAssertEqual(upper, lower)
  }

  func testASimulatorSocketIsNamedForItsSimulator() {
    let path = FBAXBridgeSocket.path(forSimulator: "AE4DEFD9-F94B-4543-84F1-849D4B5C4351")
    XCTAssertEqual(path, "\(FBAXBridgeSocket.directory)/AE4DEFD9F94B454384F1849D4B5C4351.sock")
    XCTAssertTrue(path.hasSuffix(FBAXBridgeSocket.suffix))
  }

  // `bind` truncates rather than failing, so the margin is checked against the real limit.
  func testASimulatorSocketPathFitsInSunPath() {
    let path = FBAXBridgeSocket.path(forSimulator: "AE4DEFD9-F94B-4543-84F1-849D4B5C4351")
    XCTAssertLessThan(
      path.utf8.count, FBAXBridgeConnection.sunPathCapacity, "\(path) is \(path.utf8.count) bytes")
  }
}

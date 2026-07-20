/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Foundation
// Matches the existing XCTest-based FBSimulatorControl unit suite; this target is
// XCTest-configured (no swift_testing), so Swift Testing @Test cases would not run.
// ast-grep-ignore: swift-testing/swift/no-new-xctest
import XCTest

/// Coverage of the app-context REPL reattach helpers: the deterministic socket
/// path (and its stable hash), the liveness probe, and stale-socket reaping.
final class FBSimulatorReplSocketTests: XCTestCase {

  // MARK: - stableHashHex

  func testStableHashMatchesKnownFNV1aVectors() {
    // Canonical FNV-1a 64-bit vectors. Pinning them guards against silently
    // switching to a per-process hash (e.g. `Hasher`), which would give a
    // different socket path on every run and break reattach.
    XCTAssertEqual(stableHashHex(""), "cbf29ce484222325")
    XCTAssertEqual(stableHashHex("a"), "af63dc4c8601ec8c")
  }

  func testStableHashIsDeterministic() {
    XCTAssertEqual(stableHashHex("com.example.app"), stableHashHex("com.example.app"))
  }

  func testStableHashIsAlways16HexDigits() {
    for input in ["", "a", "com.facebook.SomeVeryLongBundleIdentifier.Extension"] {
      let hex = stableHashHex(input)
      XCTAssertEqual(hex.count, 16, "expected 16 digits for \(input.debugDescription)")
      XCTAssertTrue(hex.allSatisfy { $0.isHexDigit }, "expected hex digits for \(input.debugDescription)")
    }
  }

  func testStableHashDistinguishesInputs() {
    XCTAssertNotEqual(stableHashHex("a"), stableHashHex("b"))
  }

  // MARK: - replSocketPath

  func testSocketPathHasExpectedShape() {
    let path = replSocketPath(udid: "SOME-UDID", bundleID: "com.example.app")
    XCTAssertTrue(path.hasPrefix("/tmp/idb_repl_"), path)
    XCTAssertTrue(path.hasSuffix(".sock"), path)
    // The leading "/tmp/idb_repl_<uid>" directory is variable-length (the uid
    // differs by user), so pin the basename shape instead: 16 hex digits + ".sock".
    let base = (path as NSString).lastPathComponent
    let hash = String(base.dropLast(".sock".count))
    XCTAssertEqual(hash.count, 16, path)
    XCTAssertTrue(hash.allSatisfy { $0.isHexDigit }, path)
  }

  func testSocketPathIsDeterministic() {
    XCTAssertEqual(
      replSocketPath(udid: "U", bundleID: "com.example.app"),
      replSocketPath(udid: "U", bundleID: "com.example.app"))
  }

  func testSocketPathFitsSunPathEvenForLongInputs() {
    // The reason the path is hashed: a raw udid + bundle id would overflow the
    // 104-byte sockaddr_un.sun_path. Confirm the hashed path always fits.
    let longBundleID = "com.example." + String(repeating: "a", count: 300)
    let path = replSocketPath(udid: String(repeating: "U", count: 64), bundleID: longBundleID)
    XCTAssertLessThan(path.utf8.count, 104, path)
  }

  func testSocketPathVariesByUDID() {
    XCTAssertNotEqual(
      replSocketPath(udid: "udid-1", bundleID: "com.example.app"),
      replSocketPath(udid: "udid-2", bundleID: "com.example.app"))
  }

  func testSocketPathVariesByBundleID() {
    XCTAssertNotEqual(
      replSocketPath(udid: "U", bundleID: "com.example.one"),
      replSocketPath(udid: "U", bundleID: "com.example.two"))
  }

  func testSocketPathSeparatorPreventsFieldAmbiguity() {
    // udid and bundle id are joined with a NUL separator, so shifting the
    // boundary between them yields a different path.
    XCTAssertNotEqual(
      replSocketPath(udid: "ab", bundleID: "c"),
      replSocketPath(udid: "a", bundleID: "bc"))
  }

  // MARK: - replListenerIsAlive

  func testListenerNotAliveForMissingPath() async {
    let alive = await replListenerIsAlive(at: Self.temporarySocketPath())
    XCTAssertFalse(alive)
  }

  func testListenerNotAliveForStaleSocketFile() async {
    // A bound-then-closed socket leaves its file behind with nothing listening --
    // the "app exited" case that must fall through to a relaunch.
    let path = Self.temporarySocketPath()
    let fd = Self.makeListeningSocket(at: path)
    XCTAssertGreaterThanOrEqual(fd, 0)
    Darwin.close(fd) // file remains, but nothing is listening
    defer { Darwin.unlink(path) }
    let alive = await replListenerIsAlive(at: path)
    XCTAssertFalse(alive)
  }

  func testListenerAliveForBoundSocket() async {
    let path = Self.temporarySocketPath()
    let fd = Self.makeListeningSocket(at: path)
    XCTAssertGreaterThanOrEqual(fd, 0)
    defer {
      Darwin.close(fd)
      Darwin.unlink(path)
    }
    let alive = await replListenerIsAlive(at: path)
    XCTAssertTrue(alive)
  }

  // MARK: - Helpers

  /// A short, unique `/tmp` socket path (kept in `/tmp` like the production path
  /// so it fits `sockaddr_un.sun_path`).
  private static func temporarySocketPath() -> String {
    return "/tmp/idb_repl_test_\(UUID().uuidString).sock"
  }

  /// Binds and listens an AF_UNIX socket at `path`, returning the fd (or -1). The
  /// caller closes the fd and unlinks the path.
  private static func makeListeningSocket(at path: String) -> Int32 {
    Darwin.unlink(path)
    let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return -1 }
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    guard path.utf8.count < MemoryLayout.size(ofValue: addr.sun_path) else {
      Darwin.close(fd)
      return -1
    }
    _ = withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
      path.withCString { src in memcpy(ptr, src, path.utf8.count + 1) }
    }
    let size = socklen_t(MemoryLayout<sockaddr_un>.size)
    let bound = withUnsafePointer(to: &addr) { ptr in
      ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
        Darwin.bind(fd, sockPtr, size)
      }
    }
    guard bound == 0, Darwin.listen(fd, 1) == 0 else {
      Darwin.close(fd)
      Darwin.unlink(path)
      return -1
    }
    return fd
  }
}

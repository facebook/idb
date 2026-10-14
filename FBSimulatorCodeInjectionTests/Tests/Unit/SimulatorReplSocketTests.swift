/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorCodeInjection
@testable import FBSimulatorControl
import Foundation
import Testing

/// Coverage of the app-context REPL reattach helpers: the deterministic socket
/// path (and its stable hash), the liveness probe, and stale-socket reaping.
@Suite
struct SimulatorReplSocketTests {

  // MARK: - stableHashHex

  @Test
  func stableHashMatchesKnownFNV1aVectors() {
    // Canonical FNV-1a 64-bit vectors. Pinning them guards against silently
    // switching to a per-process hash (e.g. `Hasher`), which would give a
    // different socket path on every run and break reattach.
    #expect(stableHashHex("") == "cbf29ce484222325")
    #expect(stableHashHex("a") == "af63dc4c8601ec8c")
  }

  @Test
  func stableHashIsAlways16HexDigits() {
    for input in ["", "a", "com.facebook.SomeVeryLongBundleIdentifier.Extension"] {
      let hex = stableHashHex(input)
      #expect(hex.count == 16, "expected 16 digits for \(input.debugDescription)")
      #expect(hex.allSatisfy { $0.isHexDigit }, "expected hex digits for \(input.debugDescription)")
    }
  }

  // MARK: - replSocketPath

  @Test
  func socketPathHasExpectedShape() {
    let path = replSocketPath(udid: "SOME-UDID", bundleID: "com.example.app")
    #expect(path.hasPrefix("/tmp/idb_repl_"), "\(path)")
    #expect(path.hasSuffix(".sock"), "\(path)")
    // The leading "/tmp/idb_repl_<uid>" directory is variable-length (the uid
    // differs by user), so pin the basename shape instead: 16 hex digits + ".sock".
    let base = (path as NSString).lastPathComponent
    let hash = String(base.dropLast(".sock".count))
    #expect(hash.count == 16, "\(path)")
    #expect(hash.allSatisfy { $0.isHexDigit }, "\(path)")
  }

  @Test
  func socketPathIsDeterministic() {
    #expect(
      replSocketPath(udid: "U", bundleID: "com.example.app")
        == replSocketPath(udid: "U", bundleID: "com.example.app"))
  }

  @Test
  func socketPathFitsSunPathEvenForLongInputs() {
    // The reason the path is hashed: a raw udid + bundle id would overflow the
    // 104-byte sockaddr_un.sun_path. Confirm the hashed path always fits.
    let longBundleID = "com.example." + String(repeating: "a", count: 300)
    let path = replSocketPath(udid: String(repeating: "U", count: 64), bundleID: longBundleID)
    #expect(path.utf8.count < 104, "\(path)")
  }

  @Test
  func socketPathVariesByUDID() {
    #expect(
      replSocketPath(udid: "udid-1", bundleID: "com.example.app")
        != replSocketPath(udid: "udid-2", bundleID: "com.example.app"))
  }

  @Test
  func socketPathVariesByBundleID() {
    #expect(
      replSocketPath(udid: "U", bundleID: "com.example.one")
        != replSocketPath(udid: "U", bundleID: "com.example.two"))
  }

  @Test
  func socketPathSeparatorPreventsFieldAmbiguity() {
    // udid and bundle id are joined with a NUL separator, so shifting the
    // boundary between them yields a different path.
    #expect(
      replSocketPath(udid: "ab", bundleID: "c")
        != replSocketPath(udid: "a", bundleID: "bc"))
  }

  // MARK: - replListenerIsAlive

  @Test
  func listenerNotAliveForMissingPath() async {
    let alive = await replListenerIsAlive(at: Self.temporarySocketPath())
    #expect(!alive)
  }

  @Test
  func listenerNotAliveForStaleSocketFile() async {
    // A bound-then-closed socket leaves its file behind with nothing listening --
    // the "app exited" case that must fall through to a relaunch.
    let path = Self.temporarySocketPath()
    let fd = Self.makeListeningSocket(at: path)
    #expect(fd >= 0)
    Darwin.close(fd) // file remains, but nothing is listening
    defer { Darwin.unlink(path) }
    let alive = await replListenerIsAlive(at: path)
    #expect(!alive)
  }

  @Test
  func listenerAliveForBoundSocket() async {
    let path = Self.temporarySocketPath()
    let fd = Self.makeListeningSocket(at: path)
    #expect(fd >= 0)
    defer {
      Darwin.close(fd)
      Darwin.unlink(path)
    }
    let alive = await replListenerIsAlive(at: path)
    #expect(alive)
  }

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

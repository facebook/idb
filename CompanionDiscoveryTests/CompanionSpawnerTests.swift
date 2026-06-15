/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionDiscovery
import Darwin
import Foundation
import Testing

/// Tests the companion launch + startup-handshake logic by pointing
/// `companionPath` at fake `idb_companion` scripts (the override the public API
/// exposes for exactly this purpose).
@Suite
struct CompanionSpawnerTests {
  @Test
  func returnsCompanionInfoFromHandshake() async throws {
    try await withFakeCompanion(TestSupport.echoSocketScript) { spawner in
      let udid = TestSupport.uniqueUDID()
      let socketPath = TestSupport.shortSocketPath()
      defer { cleanUp(udid: udid, socketPath: socketPath) }

      let info = try await spawner.spawnDomainSocketServer(udid: udid, path: socketPath)
      #expect(info.udid == udid)
      #expect(info.isLocal == true)
      #expect(info.address == .domainSocket(path: socketPath))
      #expect((info.pid ?? 0) > 0)
    }
  }

  @Test
  func passesUDIDAndOnlyFilterToCompanion() async throws {
    // Records the launched argv next to the socket so we can assert on it.
    let script = """
      #!/bin/bash
      path=""
      prev=""
      for arg in "$@"; do
        if [ "$prev" = "--grpc-domain-sock" ]; then path="$arg"; fi
        prev="$arg"
      done
      echo "$*" > "$path.args"
      printf '{"grpc_path": "%s"}\\n' "$path"
      """
    try await withFakeCompanion(script) { spawner in
      let udid = TestSupport.uniqueUDID()
      let socketPath = TestSupport.shortSocketPath()
      let argsPath = socketPath + ".args"
      defer {
        cleanUp(udid: udid, socketPath: socketPath)
        unlink(argsPath)
      }

      _ = try await spawner.spawnDomainSocketServer(udid: udid, only: "simulator", path: socketPath)
      let argv = try String(contentsOfFile: argsPath, encoding: .utf8)
      #expect(argv.contains("--udid \(udid)"))
      #expect(argv.contains("--grpc-domain-sock \(socketPath)"))
      #expect(argv.contains("--only simulator"))
    }
  }

  @Test
  func omitsOnlyFilterWhenNil() async throws {
    let script = """
      #!/bin/bash
      path=""
      prev=""
      for arg in "$@"; do
        if [ "$prev" = "--grpc-domain-sock" ]; then path="$arg"; fi
        prev="$arg"
      done
      echo "$*" > "$path.args"
      printf '{"grpc_path": "%s"}\\n' "$path"
      """
    try await withFakeCompanion(script) { spawner in
      let udid = TestSupport.uniqueUDID()
      let socketPath = TestSupport.shortSocketPath()
      let argsPath = socketPath + ".args"
      defer {
        cleanUp(udid: udid, socketPath: socketPath)
        unlink(argsPath)
      }

      _ = try await spawner.spawnDomainSocketServer(udid: udid, path: socketPath)
      let argv = try String(contentsOfFile: argsPath, encoding: .utf8)
      #expect(!argv.contains("--only"))
    }
  }

  @Test
  func throwsOnSocketPathMismatch() async throws {
    let script = """
      #!/bin/bash
      printf '{"grpc_path": "/wrong/path.sock"}\\n'
      """
    try await withFakeCompanion(script) { spawner in
      let udid = TestSupport.uniqueUDID()
      let socketPath = TestSupport.shortSocketPath()
      defer { cleanUp(udid: udid, socketPath: socketPath) }

      do {
        _ = try await spawner.spawnDomainSocketServer(udid: udid, path: socketPath)
        Issue.record("expected spawnDomainSocketServer to throw")
      } catch let error as CompanionDiscoveryError {
        guard case .socketPathMismatch = error else {
          Issue.record("expected .socketPathMismatch, got \(error)")
          return
        }
      }
    }
  }

  @Test
  func throwsWhenCompanionPrintsNoHandshake() async throws {
    try await withFakeCompanion("#!/bin/bash\nexit 0\n") { spawner in
      let udid = TestSupport.uniqueUDID()
      let socketPath = TestSupport.shortSocketPath()
      defer { cleanUp(udid: udid, socketPath: socketPath) }
      await #expect(throws: CompanionDiscoveryError.self) {
        try await spawner.spawnDomainSocketServer(udid: udid, path: socketPath)
      }
    }
  }

  @Test
  func throwsWhenBinaryMissing() async throws {
    let spawner = CompanionSpawner(companionPath: "/nonexistent/idb_companion_\(UUID().uuidString)")
    let udid = TestSupport.uniqueUDID()
    let socketPath = TestSupport.shortSocketPath()
    defer { cleanUp(udid: udid, socketPath: socketPath) }
    await #expect(throws: CompanionDiscoveryError.self) {
      try await spawner.spawnDomainSocketServer(udid: udid, path: socketPath)
    }
  }

  // MARK: - Helpers

  private func withFakeCompanion(_ script: String, _ body: (CompanionSpawner) async throws -> Void) async throws {
    let fakePath = try TestSupport.makeExecutableScript(script)
    defer { try? FileManager.default.removeItem(atPath: (fakePath as NSString).deletingLastPathComponent) }
    try await body(CompanionSpawner(companionPath: fakePath))
  }

  private func cleanUp(udid: String, socketPath: String) {
    unlink(socketPath)
    try? FileManager.default.removeItem(atPath: CompanionPaths.logFilePath(forUDID: udid))
  }
}

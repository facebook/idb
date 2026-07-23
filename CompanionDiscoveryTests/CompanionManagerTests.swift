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

/// Tests the discovery orchestration: registry hit reuse, conventional-socket
/// reuse, on-demand spawn, and registry maintenance.
// Serialized because the `--udid booted` discovery path uses a fixed conventional
// socket path (`booted_companion.sock`), which would race across parallel tests.
@Suite(.serialized)
struct CompanionManagerTests {
  @Test
  func returnsExistingCompanionWithoutSpawning() async throws {
    try await withTemporaryRegistry { registry in
      let udid = TestSupport.uniqueUDID()
      let existing = CompanionInfo(udid: udid, isLocal: true, pid: 123, address: .tcp(host: "h", port: 1))
      try registry.add(existing)
      // A non-existent companion path proves no spawn is attempted on a hit.
      let manager = CompanionManager(companionPath: nonexistentCompanionPath(), registry: registry)
      let info = try await manager.companionInfo(forUDID: udid)
      #expect(info == existing)
    }
  }

  @Test
  func spawnsAndRecordsWhenMissing() async throws {
    let fakePath = try TestSupport.makeExecutableScript(TestSupport.echoSocketScript)
    defer { try? FileManager.default.removeItem(atPath: (fakePath as NSString).deletingLastPathComponent) }

    try await withTemporaryRegistry { registry in
      let manager = CompanionManager(companionPath: fakePath, registry: registry)
      let udid = TestSupport.uniqueUDID()
      let socketPath = CompanionPaths().companionSocketPath(forUDID: udid)
      defer {
        unlink(socketPath)
        try? FileManager.default.removeItem(atPath: CompanionPaths().logFilePath(forUDID: udid))
      }

      let info = try await manager.companionInfo(forUDID: udid)
      #expect(info.udid == udid)
      #expect(info.address == .domainSocket(path: socketPath))
      let recorded = try registry.companions().map(\.udid)
      #expect(recorded == [udid])
    }
  }

  @Test
  func reusesBoundConventionalSocketWithoutSpawning() async throws {
    try await withTemporaryRegistry { registry in
      let udid = TestSupport.uniqueUDID()
      let socketPath = CompanionPaths().companionSocketPath(forUDID: udid)
      let fd = TestSupport.makeListeningSocket(at: socketPath)
      defer {
        close(fd)
        unlink(socketPath)
      }
      // Non-existent companion path: if it tried to spawn, it would throw.
      let manager = CompanionManager(companionPath: nonexistentCompanionPath(), registry: registry)
      let info = try await manager.companionInfo(forUDID: udid)
      #expect(info.address == .domainSocket(path: socketPath))
      #expect(info.isLocal == true)
      #expect(info.pid == nil) // we did not spawn it
      let recorded = try registry.companions().map(\.udid)
      #expect(recorded == [udid])
    }
  }

  @Test
  func disconnectRemovesFromRegistry() async throws {
    try await withTemporaryRegistry { registry in
      let udid = TestSupport.uniqueUDID()
      try registry.add(CompanionInfo(udid: udid, isLocal: true, pid: nil, address: .domainSocket(path: "/tmp/x.sock")))
      let manager = CompanionManager(companionPath: nonexistentCompanionPath(), registry: registry)
      try manager.disconnect(udid: udid)
      let companions = try registry.companions()
      #expect(companions.isEmpty)
    }
  }

  @Test
  func killClearsRegistry() async throws {
    try await withTemporaryRegistry { registry in
      // pid nil so kill() clears the registry without signalling a real process.
      let udid = TestSupport.uniqueUDID()
      try registry.add(CompanionInfo(udid: udid, isLocal: true, pid: nil, address: .domainSocket(path: "/tmp/x.sock")))
      let manager = CompanionManager(companionPath: nonexistentCompanionPath(), registry: registry)
      try manager.kill()
      let companions = try registry.companions()
      #expect(companions.isEmpty)
    }
  }

  @Test
  func prunesStaleDomainSocketEntryAndSpawns() async throws {
    let fakePath = try TestSupport.makeExecutableScript(TestSupport.echoSocketScript)
    defer { try? FileManager.default.removeItem(atPath: (fakePath as NSString).deletingLastPathComponent) }

    try await withTemporaryRegistry { registry in
      let manager = CompanionManager(companionPath: fakePath, registry: registry)
      let udid = TestSupport.uniqueUDID()
      let socketPath = CompanionPaths().companionSocketPath(forUDID: udid)
      defer {
        unlink(socketPath)
        try? FileManager.default.removeItem(atPath: CompanionPaths().logFilePath(forUDID: udid))
      }

      // A stale entry: a domain socket path that nothing is listening on.
      try registry.add(CompanionInfo(udid: udid, isLocal: true, pid: nil, address: .domainSocket(path: socketPath)))

      let info = try await manager.companionInfo(forUDID: udid)
      // The dead entry was pruned and a fresh companion spawned (so it has a pid).
      #expect(info.udid == udid)
      #expect(info.address == .domainSocket(path: socketPath))
      #expect(info.pid != nil)
      let recorded = try registry.companions().count
      #expect(recorded == 1)
    }
  }

  @Test
  func returnsLiveDomainSocketEntryWithoutSpawning() async throws {
    try await withTemporaryRegistry { registry in
      let udid = TestSupport.uniqueUDID()
      let socketPath = CompanionPaths().companionSocketPath(forUDID: udid)
      let fd = TestSupport.makeListeningSocket(at: socketPath)
      defer {
        close(fd)
        unlink(socketPath)
      }
      let existing = CompanionInfo(udid: udid, isLocal: true, pid: nil, address: .domainSocket(path: socketPath))
      try registry.add(existing)
      // Non-existent companion path: if it tried to spawn, it would throw.
      let manager = CompanionManager(companionPath: nonexistentCompanionPath(), registry: registry)
      let info = try await manager.companionInfo(forUDID: udid)
      #expect(info == existing)
    }
  }

  // MARK: - defaultCompanion

  @Test
  func defaultCompanionReturnsTheOneReachableCompanion() async throws {
    try await withTemporaryRegistry { registry in
      let udid = TestSupport.uniqueUDID()
      let socketPath = TestSupport.shortSocketPath()
      let fd = TestSupport.makeListeningSocket(at: socketPath)
      defer {
        close(fd)
        unlink(socketPath)
      }
      let existing = CompanionInfo(udid: udid, isLocal: true, pid: nil, address: .domainSocket(path: socketPath))
      try registry.add(existing)
      // Non-existent companion path: if it tried to spawn, it would throw.
      let manager = CompanionManager(companionPath: nonexistentCompanionPath(), registry: registry)
      let info = try await manager.defaultCompanion()
      #expect(info == existing)
    }
  }

  @Test
  func defaultCompanionFailsWhenMultipleAreReachable() async throws {
    try await withTemporaryRegistry { registry in
      let socketA = TestSupport.shortSocketPath()
      let socketB = TestSupport.shortSocketPath()
      let fdA = TestSupport.makeListeningSocket(at: socketA)
      let fdB = TestSupport.makeListeningSocket(at: socketB)
      defer {
        close(fdA)
        unlink(socketA)
        close(fdB)
        unlink(socketB)
      }
      try registry.add(CompanionInfo(udid: TestSupport.uniqueUDID(), isLocal: true, pid: nil, address: .domainSocket(path: socketA)))
      try registry.add(CompanionInfo(udid: TestSupport.uniqueUDID(), isLocal: true, pid: nil, address: .domainSocket(path: socketB)))
      let manager = CompanionManager(companionPath: nonexistentCompanionPath(), registry: registry)
      do {
        _ = try await manager.defaultCompanion()
        Issue.record("expected defaultCompanion to throw")
      } catch let error as CompanionDiscoveryError {
        guard case .multipleCompanions = error else {
          Issue.record("expected .multipleCompanions, got \(error)")
          return
        }
      }
    }
  }

  @Test
  func defaultCompanionSpawnsWithUDIDBootedWhenNoneAvailable() async throws {
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
    let fakePath = try TestSupport.makeExecutableScript(script)
    defer { try? FileManager.default.removeItem(atPath: (fakePath as NSString).deletingLastPathComponent) }

    try await withTemporaryRegistry { registry in
      // The `--udid booted` companion uses the conventional socket path for "booted".
      let bootedSocketPath = CompanionPaths().companionSocketPath(forUDID: "booted")
      let argsPath = bootedSocketPath + ".args"
      unlink(bootedSocketPath) // clear any leftover from a prior run
      defer {
        unlink(bootedSocketPath)
        unlink(argsPath)
        try? FileManager.default.removeItem(atPath: CompanionPaths().logFilePath(forUDID: "booted"))
      }

      let manager = CompanionManager(companionPath: fakePath, registry: registry)
      let info = try await manager.defaultCompanion()
      #expect(info.address == .domainSocket(path: bootedSocketPath))
      let argv = try String(contentsOfFile: argsPath, encoding: .utf8)
      #expect(argv.contains("--udid booted"))
      #expect(argv.contains("--only simulator"))
      let recorded = try registry.companions().map(\.udid)
      #expect(recorded == ["booted"])
    }
  }

  @Test
  func defaultCompanionReturnsReachableAndPrunesDead() async throws {
    try await withTemporaryRegistry { registry in
      let aliveUdid = TestSupport.uniqueUDID()
      let deadUdid = TestSupport.uniqueUDID()
      let aliveSocket = TestSupport.shortSocketPath()
      let deadSocket = TestSupport.shortSocketPath() // never bound -> not reachable
      let fd = TestSupport.makeListeningSocket(at: aliveSocket)
      defer {
        close(fd)
        unlink(aliveSocket)
      }
      let alive = CompanionInfo(udid: aliveUdid, isLocal: true, pid: nil, address: .domainSocket(path: aliveSocket))
      try registry.add(alive)
      try registry.add(CompanionInfo(udid: deadUdid, isLocal: true, pid: nil, address: .domainSocket(path: deadSocket)))
      // Non-existent companion path: if it tried to spawn, it would throw.
      let manager = CompanionManager(companionPath: nonexistentCompanionPath(), registry: registry)
      let info = try await manager.defaultCompanion()
      #expect(info == alive)
      // The unreachable entry is pruned, leaving only the live companion.
      let recorded = try registry.companions().map(\.udid)
      #expect(recorded == [aliveUdid])
    }
  }

  @Test
  func defaultCompanionFailsWhenSpawnFails() async throws {
    try await withTemporaryRegistry { registry in
      let bootedSocketPath = CompanionPaths().companionSocketPath(forUDID: "booted")
      unlink(bootedSocketPath) // ensure the booted-target spawn path is not already bound
      defer {
        unlink(bootedSocketPath)
        try? FileManager.default.removeItem(atPath: CompanionPaths().logFilePath(forUDID: "booted"))
      }
      // Empty registry + a companion binary that does not exist: the `--udid booted`
      // spawn fails, so discovery fails.
      let manager = CompanionManager(companionPath: nonexistentCompanionPath(), registry: registry)
      await #expect(throws: CompanionDiscoveryError.self) {
        try await manager.defaultCompanion()
      }
    }
  }

  // MARK: - Versioning

  @Test
  func versionTwoSpawnsIdb2CompanionAndRecords() async throws {
    let fakePath = try TestSupport.makeExecutableScript(TestSupport.idb2CompanionScript)
    defer { try? FileManager.default.removeItem(atPath: (fakePath as NSString).deletingLastPathComponent) }

    try await withTemporaryRegistry { registry in
      let manager = CompanionManager(version: .v2, companionPath: fakePath, registry: registry)
      let udid = TestSupport.uniqueUDID()
      let socketPath = CompanionPaths(version: .v2).companionSocketPath(forUDID: udid)
      let argsPath = socketPath + ".args"
      defer {
        unlink(socketPath)
        unlink(argsPath)
        try? FileManager.default.removeItem(atPath: CompanionPaths(version: .v2).logFilePath(forUDID: udid))
      }

      let info = try await manager.companionInfo(forUDID: udid)
      #expect(info.address == .domainSocket(path: socketPath))
      #expect(info.pid != nil) // freshly spawned
      // Launched idb2's `companion` subcommand and recorded the companion.
      let argv = try String(contentsOfFile: argsPath, encoding: .utf8)
      #expect(argv.contains("--udid \(udid)"))
      #expect(argv.contains("companion"))
      #expect(try registry.companions().map(\.udid) == [udid])
    }
  }

  // MARK: - Helpers

  private func nonexistentCompanionPath() -> String {
    "/nonexistent/idb_companion_\(UUID().uuidString)"
  }

  private func withTemporaryRegistry(_ body: (CompanionRegistry) async throws -> Void) async throws {
    let directory = TestSupport.makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(atPath: directory) }
    let statePath = (directory as NSString).appendingPathComponent("state")
    try await body(CompanionRegistry(stateFilePath: statePath))
  }
}

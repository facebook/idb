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
@Suite
struct CompanionManagerTests {
  @Test
  func returnsExistingCompanionWithoutSpawning() throws {
    try withTemporaryRegistry { registry in
      let udid = TestSupport.uniqueUDID()
      let existing = CompanionInfo(udid: udid, isLocal: true, pid: 123, address: .tcp(host: "h", port: 1))
      try registry.add(existing)
      // A non-existent companion path proves no spawn is attempted on a hit.
      let manager = CompanionManager(companionPath: nonexistentCompanionPath(), registry: registry)
      let info = try manager.companionInfo(forUDID: udid)
      #expect(info == existing)
    }
  }

  @Test
  func spawnsAndRecordsWhenMissing() throws {
    let fakePath = try TestSupport.makeExecutableScript(TestSupport.echoSocketScript)
    defer { try? FileManager.default.removeItem(atPath: (fakePath as NSString).deletingLastPathComponent) }

    try withTemporaryRegistry { registry in
      let manager = CompanionManager(companionPath: fakePath, registry: registry)
      let udid = TestSupport.uniqueUDID()
      let socketPath = CompanionPaths.companionSocketPath(forUDID: udid)
      defer {
        unlink(socketPath)
        try? FileManager.default.removeItem(atPath: CompanionPaths.logFilePath(forUDID: udid))
      }

      let info = try manager.companionInfo(forUDID: udid)
      #expect(info.udid == udid)
      #expect(info.address == .domainSocket(path: socketPath))
      let recorded = try registry.companions().map(\.udid)
      #expect(recorded == [udid])
    }
  }

  @Test
  func reusesBoundConventionalSocketWithoutSpawning() throws {
    try withTemporaryRegistry { registry in
      let udid = TestSupport.uniqueUDID()
      let socketPath = CompanionPaths.companionSocketPath(forUDID: udid)
      let fd = TestSupport.makeListeningSocket(at: socketPath)
      defer {
        close(fd)
        unlink(socketPath)
      }
      // Non-existent companion path: if it tried to spawn, it would throw.
      let manager = CompanionManager(companionPath: nonexistentCompanionPath(), registry: registry)
      let info = try manager.companionInfo(forUDID: udid)
      #expect(info.address == .domainSocket(path: socketPath))
      #expect(info.isLocal == true)
      #expect(info.pid == nil) // we did not spawn it
      let recorded = try registry.companions().map(\.udid)
      #expect(recorded == [udid])
    }
  }

  @Test
  func disconnectRemovesFromRegistry() throws {
    try withTemporaryRegistry { registry in
      let udid = TestSupport.uniqueUDID()
      try registry.add(CompanionInfo(udid: udid, isLocal: true, pid: nil, address: .domainSocket(path: "/tmp/x.sock")))
      let manager = CompanionManager(companionPath: nonexistentCompanionPath(), registry: registry)
      try manager.disconnect(udid: udid)
      let companions = try registry.companions()
      #expect(companions.isEmpty)
    }
  }

  @Test
  func killClearsRegistry() throws {
    try withTemporaryRegistry { registry in
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
  func prunesStaleDomainSocketEntryAndSpawns() throws {
    let fakePath = try TestSupport.makeExecutableScript(TestSupport.echoSocketScript)
    defer { try? FileManager.default.removeItem(atPath: (fakePath as NSString).deletingLastPathComponent) }

    try withTemporaryRegistry { registry in
      let manager = CompanionManager(companionPath: fakePath, registry: registry)
      let udid = TestSupport.uniqueUDID()
      let socketPath = CompanionPaths.companionSocketPath(forUDID: udid)
      defer {
        unlink(socketPath)
        try? FileManager.default.removeItem(atPath: CompanionPaths.logFilePath(forUDID: udid))
      }

      // A stale entry: a domain socket path that nothing is listening on.
      try registry.add(CompanionInfo(udid: udid, isLocal: true, pid: nil, address: .domainSocket(path: socketPath)))

      let info = try manager.companionInfo(forUDID: udid)
      // The dead entry was pruned and a fresh companion spawned (so it has a pid).
      #expect(info.udid == udid)
      #expect(info.address == .domainSocket(path: socketPath))
      #expect(info.pid != nil)
      let recorded = try registry.companions().count
      #expect(recorded == 1)
    }
  }

  @Test
  func returnsLiveDomainSocketEntryWithoutSpawning() throws {
    try withTemporaryRegistry { registry in
      let udid = TestSupport.uniqueUDID()
      let socketPath = CompanionPaths.companionSocketPath(forUDID: udid)
      let fd = TestSupport.makeListeningSocket(at: socketPath)
      defer {
        close(fd)
        unlink(socketPath)
      }
      let existing = CompanionInfo(udid: udid, isLocal: true, pid: nil, address: .domainSocket(path: socketPath))
      try registry.add(existing)
      // Non-existent companion path: if it tried to spawn, it would throw.
      let manager = CompanionManager(companionPath: nonexistentCompanionPath(), registry: registry)
      let info = try manager.companionInfo(forUDID: udid)
      #expect(info == existing)
    }
  }

  // MARK: - Helpers

  private func nonexistentCompanionPath() -> String {
    "/nonexistent/idb_companion_\(UUID().uuidString)"
  }

  private func withTemporaryRegistry(_ body: (CompanionRegistry) throws -> Void) throws {
    let directory = TestSupport.makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(atPath: directory) }
    let statePath = (directory as NSString).appendingPathComponent("state")
    try body(CompanionRegistry(stateFilePath: statePath))
  }
}

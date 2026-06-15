/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionDiscovery
import Foundation
import Testing

/// Exercises the registry CRUD operations and confirms it reads/writes the
/// Python-compatible state-file format. Each test uses an isolated temporary
/// state file, so nothing touches the real `/tmp/idb/state`.
@Suite
struct CompanionRegistryTests {
  @Test
  func emptyWhenNoFileExists() throws {
    try withTemporaryStateFile { statePath in
      let registry = CompanionRegistry(stateFilePath: statePath)
      let companions = try registry.companions()
      #expect(companions.isEmpty)
    }
  }

  @Test
  func addThenReadBack() throws {
    try withTemporaryStateFile { statePath in
      let registry = CompanionRegistry(stateFilePath: statePath)
      let info = CompanionInfo(udid: "u1", isLocal: true, pid: 1, address: .domainSocket(path: "/tmp/u1.sock"))
      try registry.add(info)
      let companions = try registry.companions()
      #expect(companions == [info])
    }
  }

  @Test
  func addReplacesEntryWithSameUDID() throws {
    try withTemporaryStateFile { statePath in
      let registry = CompanionRegistry(stateFilePath: statePath)
      try registry.add(CompanionInfo(udid: "u1", isLocal: true, pid: 1, address: .domainSocket(path: "/tmp/old.sock")))
      try registry.add(CompanionInfo(udid: "u1", isLocal: true, pid: 2, address: .domainSocket(path: "/tmp/new.sock")))
      let companions = try registry.companions()
      #expect(companions.count == 1)
      #expect(companions.first?.pid == 2)
      #expect(companions.first?.address == .domainSocket(path: "/tmp/new.sock"))
    }
  }

  @Test
  func keepsMultipleEntriesSortedByUDID() throws {
    try withTemporaryStateFile { statePath in
      let registry = CompanionRegistry(stateFilePath: statePath)
      try registry.add(CompanionInfo(udid: "b", isLocal: true, pid: nil, address: .domainSocket(path: "/tmp/b.sock")))
      try registry.add(CompanionInfo(udid: "a", isLocal: true, pid: nil, address: .domainSocket(path: "/tmp/a.sock")))
      let udids = try registry.companions().map(\.udid)
      #expect(udids == ["a", "b"])
    }
  }

  @Test
  func removeByUDID() throws {
    try withTemporaryStateFile { statePath in
      let registry = CompanionRegistry(stateFilePath: statePath)
      try registry.add(CompanionInfo(udid: "u1", isLocal: true, pid: nil, address: .domainSocket(path: "/tmp/u1.sock")))
      try registry.add(CompanionInfo(udid: "u2", isLocal: true, pid: nil, address: .domainSocket(path: "/tmp/u2.sock")))
      let removed = try registry.remove(udid: "u1")
      #expect(removed.map(\.udid) == ["u1"])
      let remaining = try registry.companions().map(\.udid)
      #expect(remaining == ["u2"])
    }
  }

  @Test
  func removeByAddress() throws {
    try withTemporaryStateFile { statePath in
      let registry = CompanionRegistry(stateFilePath: statePath)
      try registry.add(CompanionInfo(udid: "u1", isLocal: false, pid: nil, address: .tcp(host: "h", port: 1)))
      try registry.add(CompanionInfo(udid: "u2", isLocal: true, pid: nil, address: .domainSocket(path: "/tmp/u2.sock")))
      _ = try registry.remove(address: .tcp(host: "h", port: 1))
      let remaining = try registry.companions().map(\.udid)
      #expect(remaining == ["u2"])
    }
  }

  @Test
  func clearEmptiesAndReturnsRemoved() throws {
    try withTemporaryStateFile { statePath in
      let registry = CompanionRegistry(stateFilePath: statePath)
      try registry.add(CompanionInfo(udid: "u1", isLocal: true, pid: nil, address: .domainSocket(path: "/tmp/u1.sock")))
      let cleared = try registry.clear()
      #expect(cleared.map(\.udid) == ["u1"])
      let companions = try registry.companions()
      #expect(companions.isEmpty)
    }
  }

  @Test
  func persistsAcrossInstances() throws {
    try withTemporaryStateFile { statePath in
      let info = CompanionInfo(udid: "u1", isLocal: true, pid: 1, address: .domainSocket(path: "/tmp/u1.sock"))
      try CompanionRegistry(stateFilePath: statePath).add(info)
      let companions = try CompanionRegistry(stateFilePath: statePath).companions()
      #expect(companions == [info])
    }
  }

  @Test
  func writesPythonCompatibleJSON() throws {
    try withTemporaryStateFile { statePath in
      let registry = CompanionRegistry(stateFilePath: statePath)
      try registry.add(CompanionInfo(udid: "u1", isLocal: true, pid: 11, address: .domainSocket(path: "/tmp/u1.sock")))
      try registry.add(CompanionInfo(udid: "u2", isLocal: false, pid: 22, address: .tcp(host: "h", port: 9)))

      let data = try Data(contentsOf: URL(fileURLWithPath: statePath))
      let parsed = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
      let array = try #require(parsed)
      #expect(array.count == 2)
      // Entries are sorted by udid: u1 (domain socket) then u2 (TCP).
      #expect(array[0]["path"] as? String == "/tmp/u1.sock")
      #expect(array[0]["pid"] as? Int == 11)
      #expect(array[0]["is_local"] as? Bool == true)
      #expect(array[1]["host"] as? String == "h")
      #expect(array[1]["port"] as? Int == 9)
    }
  }

  @Test
  func treatsInvalidStateFileAsEmpty() throws {
    try withTemporaryStateFile { statePath in
      try "this is not json".write(toFile: statePath, atomically: true, encoding: .utf8)
      let registry = CompanionRegistry(stateFilePath: statePath)
      let companions = try registry.companions()
      #expect(companions.isEmpty)
    }
  }

  // MARK: - Helpers

  /// Runs `body` with a path to a state file inside a fresh temporary directory,
  /// removing the directory afterwards.
  private func withTemporaryStateFile(_ body: (String) throws -> Void) throws {
    let directory = TestSupport.makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(atPath: directory) }
    try body((directory as NSString).appendingPathComponent("state"))
  }
}

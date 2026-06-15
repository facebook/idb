/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
import Foundation

/// A persistent registry of running companions, keyed by `udid`, stored as JSON
/// at `CompanionPaths.stateFile`.
public final class CompanionRegistry {
  private let stateFilePath: String
  private let lockTimeout: TimeInterval
  private let lockRetryInterval: useconds_t

  public init(stateFilePath: String = CompanionPaths.stateFile) {
    self.stateFilePath = stateFilePath
    self.lockTimeout = 3.0
    self.lockRetryInterval = 50_000 // 50ms, matching `_open_lockfile`.
  }

  /// All recorded companions, sorted by udid.
  public func companions() throws -> [CompanionInfo] {
    try withLock { try readLocked() }
  }

  /// Records a companion, replacing any existing entry with the same udid.
  public func add(_ companion: CompanionInfo) throws {
    try withLock {
      var companions = try readLocked()
      if let index = companions.firstIndex(where: { $0.udid == companion.udid }) {
        companions[index] = companion
      } else {
        companions.append(companion)
      }
      try writeLocked(companions)
    }
  }

  /// Removes the companion with the given udid, if any, returning what was
  /// removed.
  @discardableResult
  public func remove(udid: String) throws -> [CompanionInfo] {
    try withLock {
      var companions = try readLocked()
      let removed = companions.filter { $0.udid == udid }
      companions.removeAll { $0.udid == udid }
      try writeLocked(companions)
      return removed
    }
  }

  /// Removes the companion at the given address, if any, returning what was
  /// removed.
  @discardableResult
  public func remove(address: CompanionAddress) throws -> [CompanionInfo] {
    try withLock {
      var companions = try readLocked()
      let removed = companions.filter { $0.address == address }
      companions.removeAll { $0.address == address }
      try writeLocked(companions)
      return removed
    }
  }

  /// Empties the registry and returns what was removed.
  @discardableResult
  public func clear() throws -> [CompanionInfo] {
    try withLock {
      let companions = try readLocked()
      try writeLocked([])
      return companions
    }
  }

  // MARK: - Locked file access

  private func readLocked() throws -> [CompanionInfo] {
    guard let data = FileManager.default.contents(atPath: stateFilePath), !data.isEmpty else {
      return []
    }
    do {
      return try JSONDecoder().decode([CompanionInfo].self, from: data).sorted { $0.udid < $1.udid }
    } catch {
      // An invalid or partially-written state file is treated as empty.
      return []
    }
  }

  private func writeLocked(_ companions: [CompanionInfo]) throws {
    try CompanionPaths.ensureBaseDirectory()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(companions.sorted { $0.udid < $1.udid })
    try data.write(to: URL(fileURLWithPath: stateFilePath))
  }

  // MARK: - Lockfile

  /// Runs `body` while holding an exclusive lock.
  private func withLock<T>(_ body: () throws -> T) throws -> T {
    try CompanionPaths.ensureBaseDirectory()
    let lockPath = stateFilePath + ".lock"
    let deadline = Date().addingTimeInterval(lockTimeout)
    var fd: Int32 = -1
    while true {
      fd = open(lockPath, O_CREAT | O_EXCL | O_RDWR, 0o644)
      if fd >= 0 {
        break
      }
      let err = errno
      if err != EEXIST {
        throw CompanionDiscoveryError.lockFailed(path: lockPath, code: err)
      }
      if Date() >= deadline {
        throw CompanionDiscoveryError.lockTimedOut(path: lockPath)
      }
      usleep(lockRetryInterval)
    }
    defer {
      close(fd)
      unlink(lockPath)
    }
    return try body()
  }
}

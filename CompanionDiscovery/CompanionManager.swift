/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
import Foundation

/// Discovers running companions and starts them on demand, keyed by simulator /
/// device udid.
public final class CompanionManager {
  public let registry: CompanionRegistry
  private let spawner: CompanionSpawner

  /// - Parameters:
  ///   - companionPath: path to the `idb_companion` binary used to spawn
  ///     companions on demand. Defaults to
  ///     `CompanionPaths.defaultCompanionExecutable`; pass an explicit path to
  ///     override it (e.g. a test fixture).
  ///   - deviceSetPath: optional custom CoreSimulator device set.
  ///   - registry: the backing companion registry.
  public init(
    companionPath: String = CompanionPaths.defaultCompanionExecutable,
    deviceSetPath: String? = nil,
    registry: CompanionRegistry = CompanionRegistry()
  ) {
    self.registry = registry
    self.spawner = CompanionSpawner(companionPath: companionPath, deviceSetPath: deviceSetPath)
  }

  /// Returns the companion to use for `udid`: the one already recorded in the
  /// registry if present, otherwise a freshly discovered or spawned one.
  public func companionInfo(forUDID udid: String) throws -> CompanionInfo {
    let companions = try registry.companions()
    if let existing = companions.first(where: { $0.udid == udid }) {
      return existing
    }
    return try spawnCompanionServer(udid: udid)
  }

  /// Ensures a companion exists for `udid` and records it.
  @discardableResult
  public func spawnCompanionServer(udid: String, only: String? = nil) throws -> CompanionInfo {
    let path = CompanionPaths.companionSocketPath(forUDID: udid)
    let info: CompanionInfo
    if CompanionConnectivity.isDomainSocketBound(path: path) {
      // A companion is already serving this path, so reuse it.
      info = CompanionInfo(udid: udid, isLocal: true, pid: nil, address: .domainSocket(path: path))
    } else {
      info = try spawner.spawnDomainSocketServer(udid: udid, only: only, path: path)
    }
    try registry.add(info)
    return info
  }

  /// Removes the companion for `udid` from the registry.
  public func disconnect(udid: String) throws {
    try registry.remove(udid: udid)
  }

  /// Clears the registry and SIGKILLs every companion it recorded a pid for.
  public func kill() throws {
    let cleared = try registry.clear()
    for companion in cleared {
      guard let pid = companion.pid else {
        continue
      }
      Darwin.kill(pid, SIGKILL)
    }
  }
}

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

  /// Pseudo-udid passed as `--udid booted`, telling a spawned companion to attach
  /// to the single booted simulator/device.
  private static let bootedTargetUDID = "booted"

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
  /// registry if it is still reachable, otherwise a freshly discovered or
  /// spawned one. A recorded companion that has gone away (e.g. it exited but
  /// left its socket and registry entry behind) is pruned and replaced.
  ///
  /// When a companion is spawned, `idleShutdownTime` (if set) is forwarded as
  /// `--idle-shutdown-time`; it has no effect when an existing companion is reused.
  public func companionInfo(forUDID udid: String, idleShutdownTime: TimeInterval? = nil) async throws -> CompanionInfo {
    let companions = try registry.companions()
    if let existing = companions.first(where: { $0.udid == udid }) {
      if isAlive(existing) {
        return existing
      }
      try registry.remove(udid: udid)
    }
    return try await spawnCompanionServer(udid: udid, idleShutdownTime: idleShutdownTime)
  }

  /// Returns the companion to use when the caller has not named a specific target:
  /// - exactly one companion is recorded and reachable -> returns it;
  /// - no companion is reachable -> spawns a local companion with `--udid booted`
  ///   (the companion attaches to the single booted simulator/device) and returns
  ///   it; if that spawn fails, discovery fails;
  /// - more than one companion is reachable -> discovery fails (ambiguous).
  ///
  /// Recorded companions that have gone away are pruned. `idleShutdownTime`, if
  /// set, is forwarded to a spawned companion.
  public func defaultCompanion(idleShutdownTime: TimeInterval? = nil) async throws -> CompanionInfo {
    var reachable: [CompanionInfo] = []
    for companion in try registry.companions() {
      if isAlive(companion) {
        reachable.append(companion)
      } else {
        // Drop entries whose companion has gone away.
        try registry.remove(udid: companion.udid)
      }
    }

    if reachable.count > 1 {
      throw CompanionDiscoveryError.multipleCompanions(udids: reachable.map(\.udid))
    }
    if let existing = reachable.first {
      return existing
    }
    return try await spawnCompanionServer(udid: Self.bootedTargetUDID, idleShutdownTime: idleShutdownTime)
  }

  /// Whether a recorded companion is still reachable. Domain-socket companions
  /// are probed by connecting; TCP/remote companions can't be probed cheaply, so
  /// they are trusted.
  private func isAlive(_ companion: CompanionInfo) -> Bool {
    switch companion.address {
    case let .domainSocket(path):
      return CompanionConnectivity.isDomainSocketBound(path: path)
    case .tcp:
      return true
    }
  }

  /// Ensures a companion exists for `udid` and records it. `idleShutdownTime`, if
  /// set, is forwarded to a newly spawned companion as `--idle-shutdown-time`.
  @discardableResult
  public func spawnCompanionServer(udid: String, only: String? = nil, idleShutdownTime: TimeInterval? = nil) async throws -> CompanionInfo {
    let path = CompanionPaths.companionSocketPath(forUDID: udid)
    let info: CompanionInfo
    if CompanionConnectivity.isDomainSocketBound(path: path) {
      // A companion is already serving this path, so reuse it.
      info = CompanionInfo(udid: udid, isLocal: true, pid: nil, address: .domainSocket(path: path))
    } else {
      info = try await spawner.spawnDomainSocketServer(udid: udid, only: only, path: path, idleShutdownTime: idleShutdownTime)
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

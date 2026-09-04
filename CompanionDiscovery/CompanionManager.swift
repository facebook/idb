/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

#if os(macOS)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#else
#error("Unknown platform")
#endif

/// Discovers running companions and starts them on demand, keyed by simulator /
/// device udid.
public final class CompanionManager {
  public let registry: CompanionRegistry
  private let spawner: CompanionSpawner
  private let paths: CompanionPaths

  /// Pseudo-udid passed as `--udid booted`, telling a spawned companion to attach
  /// to the single booted simulator.
  private static let bootedTargetUDID = "booted"

  /// `--only` filter passed alongside `--udid booted` so the booted-target search
  /// is scoped to simulators.
  private static let simulatorOnlyFilter = "simulator"

  /// `version` selects the base directory for the registry, logs and sockets (see `CompanionPaths`),
  /// so v1 and v2 managers never collide. `companionPath` and `registry` default to that version's
  /// executable and state file.
  public init(
    version: CompanionVersion = .v1,
    companionPath: String? = nil,
    deviceSetPath: String? = nil,
    registry: CompanionRegistry? = nil
  ) {
    let paths = CompanionPaths(version: version)
    self.paths = paths
    self.registry = registry ?? CompanionRegistry(stateFilePath: paths.stateFile)
    self.spawner = CompanionSpawner(
      paths: paths,
      companionPath: companionPath ?? paths.defaultCompanionExecutable,
      deviceSetPath: deviceSetPath)
  }

  /// Returns the companion to use for `udid`: the one already recorded in the
  /// registry if it is still reachable, otherwise a freshly discovered or
  /// spawned one. A recorded companion that has gone away (e.g. it exited but
  /// left its socket and registry entry behind) is pruned and replaced.
  ///
  /// When a companion is spawned, `idleShutdownTime` (if set) is forwarded as
  /// `--idle-shutdown-time`; it has no effect when an existing companion is reused.
  public func companionInfo(forUDID udid: String, idleShutdownTime: Int? = nil) async throws -> CompanionInfo {
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
  ///   `--only simulator` (it attaches to the single booted simulator) and returns
  ///   it; if that spawn fails, discovery fails;
  /// - more than one companion is reachable -> discovery fails (ambiguous).
  ///
  /// Recorded companions that have gone away are pruned. `idleShutdownTime`, if
  /// set, is forwarded to a spawned companion.
  public func defaultCompanion(idleShutdownTime: Int? = nil) async throws -> CompanionInfo {
    var reachable: [CompanionInfo] = []
    for companion in try registry.companions() {
      if isAlive(companion) {
        reachable.append(companion)
      } else {
        try registry.remove(udid: companion.udid)
      }
    }

    if reachable.count > 1 {
      throw CompanionDiscoveryError.multipleCompanions(udids: reachable.map(\.udid))
    }
    if let existing = reachable.first {
      return existing
    }
    return try await spawnCompanionServer(
      udid: Self.bootedTargetUDID,
      only: Self.simulatorOnlyFilter,
      idleShutdownTime: idleShutdownTime)
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
  func spawnCompanionServer(udid: String, only: String? = nil, idleShutdownTime: Int? = nil) async throws -> CompanionInfo {
    let path = paths.companionSocketPath(forUDID: udid)
    let info: CompanionInfo
    if CompanionConnectivity.isDomainSocketBound(path: path) {
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
      Platform.kill(pid, SIGKILL)
    }
  }
}

/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

/// How a CLI should reach a companion, decided from the connection options and whether the current
/// platform supports discovering a local companion. Kept free of I/O.
public enum CompanionRoute: Equatable {
  /// Connect directly to the companion at this `host:port` (still to be parsed),
  /// bypassing discovery. Corresponds to an explicit `--companion`.
  case tcp(String)
  /// Discover a running companion, or start one on demand.
  case discoverLocal
  /// Select a remote companion from the environment or companion registry.
  case selectRemote
}

/// Why a remote companion could not be selected automatically.
public enum RemoteCompanionSelectionError: Error, Equatable, CustomStringConvertible {
  case invalidEnvironmentCompanion(String)
  case noCompanions(udid: String?)
  case ambiguousCompanions(udid: String?, candidates: [CompanionInfo])

  public var description: String {
    switch self {
    case let .invalidEnvironmentCompanion(value):
      return "IDB_COMPANION expects host:port, e.g. 127.0.0.1:10882 (got '\(value)')"
    case let .noCompanions(udid):
      if let udid {
        return "No TCP companion for UDID '\(udid)' was found in /tmp/idb/state. Pass --companion <host:port>, set IDB_COMPANION, or connect that companion with idb connect."
      }
      return "No TCP companion was found in /tmp/idb/state. Pass --companion <host:port>, set IDB_COMPANION, or connect a companion with idb connect."
    case let .ambiguousCompanions(udid, candidates):
      let descriptions = candidates.map(companionDescription).joined(separator: ", ")
      if let udid {
        return "Multiple TCP companions for UDID '\(udid)' were found in /tmp/idb/state: \(descriptions). Pass --companion <host:port>."
      }
      return "Multiple TCP companions were found in /tmp/idb/state: \(descriptions). Pass --udid <udid> or --companion <host:port>."
    }
  }
}

/// Whether local companion discovery is available on this platform. Local
/// discovery spawns and connects to a local `idb_companion`, which exists only on
/// macOS; on any other platform a companion must be reached over TCP.
#if os(macOS)
public let localCompanionDiscoverySupported = true
#else
public let localCompanionDiscoverySupported = false
#endif

/// An explicit `--companion host:port` always wins; otherwise local discovery is used where it is
/// available and remote selection is used where it is not (e.g. Linux, which has no local
/// `idb_companion`).
public func planCompanionRoute(
  companion: String?,
  localAllowed: Bool = localCompanionDiscoverySupported
) -> CompanionRoute {
  if let companion {
    return .tcp(companion)
  }
  return localAllowed ? .discoverLocal : .selectRemote
}

/// Selects the TCP companion used when local discovery is unavailable.
public func selectRemoteCompanion(
  environmentCompanion: String?,
  companions: [CompanionInfo],
  udid: String?
) throws -> CompanionAddress {
  if let environmentCompanion {
    guard let address = CompanionAddress.parse(tcp: environmentCompanion) else {
      throw RemoteCompanionSelectionError.invalidEnvironmentCompanion(environmentCompanion)
    }
    return address
  }

  let candidates =
    companions
    .filter { companion in
      guard case .tcp = companion.address else {
        return false
      }
      return udid == nil || companion.udid == udid
    }
    .sorted { companionDescription($0) < companionDescription($1) }

  switch candidates.count {
  case 0:
    throw RemoteCompanionSelectionError.noCompanions(udid: udid)
  case 1:
    return candidates[0].address
  default:
    throw RemoteCompanionSelectionError.ambiguousCompanions(udid: udid, candidates: candidates)
  }
}

private func companionDescription(_ companion: CompanionInfo) -> String {
  switch companion.address {
  case let .tcp(host, port):
    return "\(companion.udid)=\(host):\(port)"
  case let .domainSocket(path):
    return "\(companion.udid)=\(path)"
  }
}

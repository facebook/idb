/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Filesystem locations for a given companion `version`. v1 shares its directory
/// with the Python `idb` client (so companions spawned or recorded by either
/// tool are mutually discoverable); v2 lives in a separate directory so the two
/// generations are tracked independently.
public struct CompanionPaths {
  /// The companion generation these paths address.
  public let version: CompanionVersion

  public init(version: CompanionVersion = .v1) {
    self.version = version
  }

  /// Default location of the binary used to spawn companions for this version:
  /// the v1 `idb_companion` server, or the v2 `idb2` CLI (whose `companion`
  /// subcommand runs the server). Both are installed at these conventional paths
  /// by the idb RPM.
  public var defaultCompanionExecutable: String {
    switch version {
    case .v1: return "/usr/local/bin/idb_companion"
    case .v2: return "/usr/local/bin/idb2"
    }
  }

  /// Base directory for all idb state. (`BASE_IDB_FILE_PATH`)
  public var baseDirectory: String {
    switch version {
    case .v1: return "/tmp/idb"
    case .v2: return "/tmp/idb2"
    }
  }

  /// The companion registry file. (`IDB_STATE_FILE_PATH`)
  public var stateFile: String {
    (baseDirectory as NSString).appendingPathComponent("state")
  }

  /// Directory holding per-target companion logs. (`IDB_LOGS_PATH`)
  public var logsDirectory: String {
    (baseDirectory as NSString).appendingPathComponent("logs")
  }

  /// The conventional domain-socket path a local companion for `udid` binds.
  public func companionSocketPath(forUDID udid: String) -> String {
    (baseDirectory as NSString).appendingPathComponent("\(udid)_companion.sock")
  }

  /// The per-target companion log path.
  public func logFilePath(forUDID udid: String) -> String {
    (logsDirectory as NSString).appendingPathComponent(udid)
  }

  /// Creates `baseDirectory` if needed.
  public func ensureBaseDirectory() throws {
    try FileManager.default.createDirectory(atPath: baseDirectory, withIntermediateDirectories: true)
  }

  /// Creates `logsDirectory` if needed.
  public func ensureLogsDirectory() throws {
    try FileManager.default.createDirectory(atPath: logsDirectory, withIntermediateDirectories: true)
  }
}

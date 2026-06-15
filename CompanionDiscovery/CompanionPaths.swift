/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Filesystem locations shared with the Python `idb` client, so that companions
/// spawned or recorded by either tool are mutually discoverable.
public enum CompanionPaths {
  /// Base directory for all idb state. (`BASE_IDB_FILE_PATH`)
  public static let baseDirectory = "/tmp/idb"

  /// The companion registry file. (`IDB_STATE_FILE_PATH`)
  public static let stateFile = "/tmp/idb/state"

  /// Directory holding per-target companion logs. (`IDB_LOGS_PATH`)
  public static let logsDirectory = "/tmp/idb/logs"

  /// Default location of the `idb_companion` binary used to spawn companions.
  public static let defaultCompanionExecutable = "/usr/local/bin/idb_companion"

  /// The conventional domain-socket path a local companion for `udid` binds.
  public static func companionSocketPath(forUDID udid: String) -> String {
    (baseDirectory as NSString).appendingPathComponent("\(udid)_companion.sock")
  }

  /// The per-target companion log path.
  public static func logFilePath(forUDID udid: String) -> String {
    (logsDirectory as NSString).appendingPathComponent(udid)
  }

  /// Creates `baseDirectory` if needed.
  public static func ensureBaseDirectory() throws {
    try FileManager.default.createDirectory(atPath: baseDirectory, withIntermediateDirectories: true)
  }

  /// Creates `logsDirectory` if needed.
  public static func ensureLogsDirectory() throws {
    try FileManager.default.createDirectory(atPath: logsDirectory, withIntermediateDirectories: true)
  }
}

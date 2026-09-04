/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
import Foundation

/// Where a persistent bridge's socket lives, and how to recognise one.
///
/// Its own file because it is shared vocabulary: two processes that never speak to each other have to
/// derive the same path for the same simulator, or each starts a bridge the other cannot find.
enum FBAXBridgeSocket {
  static let suffix = ".sock"

  /// A directory of our own beneath the per-user temporary directory, owner-only.
  ///
  /// Private rather than `/tmp` because a socket name anyone can predict is only safe if nobody else
  /// can bind it first.
  static let directory: String = {
    let base = userTemporaryDirectory()
    return "\(base.hasSuffix("/") ? String(base.dropLast()) : base)/idb-ax"
  }()

  /// From `confstr`, not `$TMPDIR`: `NSTemporaryDirectory()` honours an environment variable a harness
  /// may set to anything — it can overrun `sun_path`, be world-writable, or differ between two host
  /// processes so each spawns its own guest instead of sharing one. `confstr` answers from the uid.
  private static func userTemporaryDirectory() -> String {
    let size = confstr(_CS_DARWIN_USER_TEMP_DIR, nil, 0)
    guard size > 0 else {
      return "/tmp"
    }
    var buffer = [CChar](repeating: 0, count: size)
    guard confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, size) == size else {
      return "/tmp"
    }
    // `confstr` reports a size that includes the terminator, which has to come off before decoding.
    return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
  }

  /// Called before a spawn because `bind` does not create intermediate directories. The mode is set
  /// explicitly every time: `createDirectory` honours `attributes` only when it creates, and on the
  /// `/tmp` fallback another user could pre-create `idb-ax` with a permissive mode. Failing to set it
  /// fails closed.
  static func prepareDirectory(_ path: String = directory) throws {
    let manager = FileManager.default
    try manager.createDirectory(
      atPath: path,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: ownerOnlyPermissions]
    )
    try manager.setAttributes([.posixPermissions: ownerOnlyPermissions], ofItemAtPath: path)
  }

  /// `rwx` for the owner and nothing for anyone else.
  static let ownerOnlyPermissions = 0o700

  static func path(forConnection identifier: String) -> String {
    "\(directory)/\(identifier)\(suffix)"
  }

  /// The socket a bridge serving `udid` listens on.
  ///
  /// Named for the simulator rather than the connection, so a process can find a bridge it did not
  /// start. Case is normalised because a UDID is hex that can reach two callers in either case, and both
  /// must compute the same socket. Dashes are stripped to buy length: ten bytes spare in `sun_path`
  /// rather than six, which matters because `bind` truncates an over-long path and reports success.
  static func path(forSimulator udid: String) -> String {
    path(forConnection: udid.replacingOccurrences(of: "-", with: "").uppercased())
  }
}

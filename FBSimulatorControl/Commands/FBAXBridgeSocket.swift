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
  ///
  /// Owning the directory is also what pays for the name. `sun_path` is 104 bytes and the per-user
  /// temporary directory is 49 of them, so the old `idb_axbridge_` prefix plus a UUID no longer fits —
  /// but the prefix only existed to pick our sockets out of a directory full of other people's files,
  /// and here there are none.
  static let directory: String = {
    let base = userTemporaryDirectory()
    return "\(base.hasSuffix("/") ? String(base.dropLast()) : base)/idb-ax"
  }()

  /// The per-user temporary directory, from `confstr` rather than `$TMPDIR`.
  ///
  /// `NSTemporaryDirectory()` reads the environment variable, which a build system, CI harness or
  /// sandbox is free to set to anything. That is wrong here three times over: an arbitrary value can
  /// overrun `sun_path`, it could point somewhere world-writable, and — worst, because it fails
  /// silently — two host processes that disagree about the path would each spawn their own guest
  /// instead of sharing one, losing the reuse with no error to notice. `confstr` answers from the uid,
  /// so every process this user runs gets the same fixed-length answer.
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

  /// Creates the socket directory if it is not already there, and makes sure it is owner-only. Called
  /// before a spawn, because the guest binds into it and `bind` does not create intermediate
  /// directories.
  ///
  /// The mode is applied after the fact rather than left to `createDirectory`, which honours its
  /// `attributes` only when it actually creates something. That distinction matters on the `/tmp`
  /// fallback: `/tmp` is world-writable, so another local user could pre-create `idb-ax` there with a
  /// permissive mode, and a create call would return success on it without complaint — handing them a
  /// directory we then bind predictable socket names into. Setting the mode every time closes that,
  /// and throwing if it cannot be set fails closed rather than serving from a directory we do not
  /// actually control.
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

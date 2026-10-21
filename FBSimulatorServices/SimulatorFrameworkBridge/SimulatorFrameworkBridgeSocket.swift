/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import FBSimulatorBridgeProtocol
import FBSimulatorControl
import Foundation
import SimulatorIPC

/// Where a persistent bridge's socket lives, and how to recognise one.
///
/// Its own file because it is shared vocabulary: two processes that never speak to each other have to
/// derive the same path for the same simulator, or each starts a bridge the other cannot find.
enum SimulatorFrameworkBridgeSocket {
  static let suffix = ".sock"

  /// A directory of our own beneath the per-user temporary directory, owner-only.
  ///
  /// Private rather than `/tmp` because a socket name anyone can predict is only safe if nobody else
  /// can bind it first.
  static let directory: String = {
    // From `confstr`, not `$TMPDIR`, which a harness may set to anything: it can overrun `sun_path`, be
    // world-writable, or differ between two host processes so each spawns its own guest instead of sharing one.
    let base = TemporaryDirectory.userDirectoryPath() ?? "/tmp"
    return "\(base.hasSuffix("/") ? String(base.dropLast()) : base)/idb-sfb-v\(BridgeRequest.currentVersion)"
  }()

  /// Called before a spawn because `bind` does not create intermediate directories. The mode is set
  /// explicitly every time: `createDirectory` honours `attributes` only when it creates, and on the
  /// `/tmp` fallback another user could pre-create `idb-ax` with a permissive mode. Failing to set it
  /// fails closed.
  static func prepareDirectory(_ path: String = directory) throws {
    try IPCSocket.prepareDirectory(path)
  }

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

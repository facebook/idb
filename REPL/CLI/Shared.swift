/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import ArgumentParser
import Foundation

/// Options that only apply to the `test` context.
struct TestBundleOptions: ParsableArguments {
  @Option(name: .long, help: "Path to the test bundle.")
  var testBundlePath: String
}

/// Options that only apply to the `app` context.
struct AppOptions: ParsableArguments {
  @Option(name: .long, help: "Bundle id of the installed app to launch and inject the REPL into.")
  var bundleID: String

  @Flag(name: .long, help: "Start a new REPL session (a clean relaunch) instead of reattaching to an already-running REPL for this app.")
  var newSession = false

  var reuseSession: Bool { !newSession }
}

/// @unchecked Sendable: the lazy-creation flag is the only mutable state and is
/// guarded by `lock`; `path` is an immutable `let`.
final class SessionDirectory: @unchecked Sendable {
  let path: String
  private let lock = NSLock()
  private var created = false

  init() {
    path = (NSTemporaryDirectory() as NSString)
      .appendingPathComponent("idb_repl_\(UUID().uuidString)")
  }

  deinit {
    cleanup()
  }

  func filePath(named name: String) throws -> String {
    lock.lock()
    defer { lock.unlock() }
    if !created {
      try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
      created = true
    }
    return (path as NSString).appendingPathComponent(name)
  }

  func cleanup() {
    lock.lock()
    defer { lock.unlock() }
    if created {
      try? FileManager.default.removeItem(atPath: path)
      created = false
    }
  }
}

let sessionDirectory = SessionDirectory()

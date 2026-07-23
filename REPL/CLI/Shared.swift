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
  @Option(name: .long, help: "Bundle id of the installed app to launch and inject the REPL into. If omitted, the companion launches its bundled ReplHost app.")
  var bundleID: String?

  @Flag(name: .long, help: "Start a new REPL session (a clean relaunch) instead of reattaching to an already-running REPL for this app.")
  var newSession = false

  var reuseSession: Bool { !newSession }
}

/// Connection and toolchain options shared by every subcommand: which target or
/// companion to reach and how to compile injected code. Flattened into each subcommand
/// via `@OptionGroup`.
struct ConnectionOptions: ParsableArguments {
  @Option(
    name: .long,
    help: "UDID of the simulator to use for execution. If omitted, the single running companion is used, or one is started for the only available simulator.")
  var udid: String?

  @Option(name: .long, help: "Path to the Swift toolchain used to compile code. Defaults to the selected Xcode toolchain (xcode-select -p).")
  var toolchainPath: String?

  @Option(
    name: .long,
    help: ArgumentHelp(
      "Path to the idb_companion binary, overriding the default system installed binary.",
      visibility: .hidden))
  var idbCompanionBinary: String?

  @Option(
    name: .long,
    help: "Connect directly to a companion at host:port (e.g. 127.0.0.1:10882), bypassing discovery. Use to reach an already-running, typically remote, companion.")
  var companion: String?

  @Flag(
    name: .long,
    help: ArgumentHelp(
      "Use an unencrypted TCP connection to the companion instead of TLS.",
      visibility: .hidden))
  var plaintext = false

  /// Assembles the session config from these connection options, the report options,
  /// and the global `--reason`.
  func sessionConfig(report: ReportOptions) -> ReplSessionConfig {
    ReplSessionConfig(
      udid: udid,
      toolchainPath: toolchainPath,
      idbCompanionBinary: idbCompanionBinary,
      companion: companion,
      plaintext: plaintext,
      reportPath: report.reportPath,
      reportFailures: report.reportFailures,
      reason: GlobalOptions.shared.reason)
  }
}

/// Report options shared by every subcommand: where to write the session report and
/// whether to also record runs that fail to compile. Flattened into each subcommand via
/// `@OptionGroup`.
struct ReportOptions: ParsableArguments {
  @Option(
    name: .long,
    help: "Write a Markdown report of this session (the code run and its results) to this path. If omitted, no report is written.")
  var reportPath: String?

  @Flag(
    name: .long,
    help: "Also record runs whose code fails to compile in the report. Off by default; successful runs and runtime exceptions are always recorded.")
  var reportFailures = false
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

  /// The `artifacts/` subdirectory of the session directory, created if needed. Used
  /// to stage retrieved artifacts when no session report is being written (a report
  /// stores them next to itself instead).
  func artifactsDirectory() throws -> String {
    let directory = try filePath(named: "artifacts")
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    return directory
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

/// Session-wide facts learned from the REPL handshake.
///
/// @unchecked Sendable: `sharedFilesystem` is guarded by `lock`.
final class ReplSessionInfo: @unchecked Sendable {
  private let lock = NSLock()
  private var sharedFilesystemValue = false

  /// Whether the connected companion shares this driver's filesystem, set once
  /// from the ready handshake. When true, captured artifacts are moved into the
  /// session's artifacts directory directly; otherwise they are pulled back over
  /// gRPC and removed from the companion.
  var sharedFilesystem: Bool {
    get {
      lock.lock()
      defer { lock.unlock() }
      return sharedFilesystemValue
    }
    set {
      lock.lock()
      defer { lock.unlock() }
      sharedFilesystemValue = newValue
    }
  }
}

let replSessionInfo = ReplSessionInfo()

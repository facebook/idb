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

/// The Apple platform to compile injected code for, derived from the device
/// type the companion reports for its connected target.
enum Platform {
  case iOSSimulator
  case macOS
  case watchOSSimulator
  case tvOSSimulator

  /// Maps a companion-reported device type to the platform to compile for.
  init(deviceType: String) throws {
    switch deviceType {
    case "iphone", "ipad":
      self = .iOSSimulator
    case "mac":
      self = .macOS
    case "watch":
      self = .watchOSSimulator
    case "tv":
      self = .tvOSSimulator
    default:
      throw ValidationError("Unsupported device type reported by idb_companion: '\(deviceType)'")
    }
  }

  var sdkName: String {
    switch self {
    case .iOSSimulator: return "iphonesimulator"
    case .macOS: return "macosx"
    case .watchOSSimulator: return "watchsimulator"
    case .tvOSSimulator: return "appletvsimulator"
    }
  }

  func targetTriple(version: String) -> String {
    switch self {
    case .iOSSimulator: return "arm64-apple-ios\(version)-simulator"
    case .macOS: return "arm64-apple-macosx\(version)"
    case .watchOSSimulator: return "arm64-apple-watchos\(version)-simulator"
    case .tvOSSimulator: return "arm64-apple-tvos\(version)-simulator"
    }
  }
}

func resolveSDKPath(platform: Platform) throws -> String {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
  process.arguments = ["--sdk", platform.sdkName, "--show-sdk-path"]
  let pipe = Pipe()
  process.standardOutput = pipe
  try process.run()
  process.waitUntilExit()

  guard process.terminationStatus == 0,
    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
  else {
    throw ValidationError("Failed to resolve SDK path")
  }

  return output.trimmingCharacters(in: .whitespacesAndNewlines)
}

func resolveTargetTriple(platform: Platform) throws -> String {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
  process.arguments = ["--sdk", platform.sdkName, "--show-sdk-platform-version"]
  let pipe = Pipe()
  process.standardOutput = pipe
  try process.run()
  process.waitUntilExit()

  guard process.terminationStatus == 0,
    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
  else {
    throw ValidationError("Failed to resolve SDK platform version")
  }

  let version = output.trimmingCharacters(in: .whitespacesAndNewlines)
  return platform.targetTriple(version: version)
}

/// Resolves the Swift toolchain path. Returns `explicit` when given (e.g. the
/// `test` context derives one from the test target's `[xctoolchain]` sub-target);
/// otherwise falls back to the locally selected Xcode toolchain via
/// `xcode-select -p`, matching idb-repl-simulator.sh.
func resolveToolchainPath(explicit: String?) throws -> String {
  if let explicit {
    return explicit
  }

  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
  process.arguments = ["-p"]
  let pipe = Pipe()
  process.standardOutput = pipe
  try process.run()
  process.waitUntilExit()

  guard process.terminationStatus == 0,
    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
  else {
    throw ValidationError("Failed to resolve the selected Xcode toolchain via xcode-select; pass --toolchain-path explicitly")
  }

  let developerDirectory = output.trimmingCharacters(in: .whitespacesAndNewlines)
  return (developerDirectory as NSString).appendingPathComponent("Toolchains/XcodeDefault.xctoolchain")
}

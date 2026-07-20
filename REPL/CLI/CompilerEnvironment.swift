/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A failure while resolving the compiler environment (SDK, toolchain, or
/// target platform). Replaces `ArgumentParser.ValidationError` so this file
/// carries no dependency on the argument parser; the CLI surfaces the message
/// as-is.
struct CompilerEnvironmentError: Error, CustomStringConvertible {
  let description: String

  init(_ description: String) {
    self.description = description
  }
}

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
      throw CompilerEnvironmentError("Unsupported device type reported by idb_companion: '\(deviceType)'")
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
    throw CompilerEnvironmentError("Failed to resolve SDK path")
  }

  return output.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Resolves the LLVM target triple for compiling injected code. The OS-version
/// suffix of an Apple triple is the deployment target, which decides the newest
/// symbols the dylib may reference. It is floored at the connected target's
/// runtime OS version (reported by the companion) so injected code never links
/// against symbols the runtime lacks -- the mismatch that occurs when the local
/// SDK (e.g. iOS 27) is newer than the simulator (e.g. iOS 26.2).
///
/// `runtimeOSVersion` may be greater than the local SDK version (an older Xcode
/// against a newer runtime); the deployment target is the lower of the two,
/// since the compiler rejects a deployment target above the SDK version.
func resolveTargetTriple(platform: Platform, runtimeOSVersion: String) throws -> String {
  let sdkVersion = try resolveSDKPlatformVersion(platform: platform)
  return platform.targetTriple(
    version: DeploymentTargetVersion.floored(runtimeOSVersion: runtimeOSVersion, sdkVersion: sdkVersion))
}

/// The local SDK's platform version (e.g. "27.0"), from
/// `xcrun --sdk <name> --show-sdk-platform-version` -- the highest deployment
/// target the installed toolchain can build for.
private func resolveSDKPlatformVersion(platform: Platform) throws -> String {
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
    throw CompilerEnvironmentError("Failed to resolve SDK platform version")
  }

  return output.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Chooses the OS version to compile injected code against (the deployment
/// target in the LLVM triple). Pure and free of I/O, so it can be unit-tested
/// directly (see `CompilerEnvironmentTests`).
enum DeploymentTargetVersion {

  /// The connected target's runtime OS version, floored at the local SDK
  /// version, since the compiler rejects a deployment target above the SDK
  /// version.
  static func floored(runtimeOSVersion: String, sdkVersion: String) -> String {
    isAtMost(runtimeOSVersion, sdkVersion) ? runtimeOSVersion : sdkVersion
  }

  /// Whether dotted version `lhs` is less than or equal to `rhs`, compared
  /// component-wise numerically (so "26.2" <= "27.0" and "9.0" <= "10.0").
  /// Missing or non-numeric components count as 0.
  static func isAtMost(_ lhs: String, _ rhs: String) -> Bool {
    let lhsComponents = lhs.split(separator: ".").map { Int($0) ?? 0 }
    let rhsComponents = rhs.split(separator: ".").map { Int($0) ?? 0 }
    for index in 0..<max(lhsComponents.count, rhsComponents.count) {
      let left = index < lhsComponents.count ? lhsComponents[index] : 0
      let right = index < rhsComponents.count ? rhsComponents[index] : 0
      if left != right { return left < right }
    }
    return true
  }
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
    throw CompilerEnvironmentError("Failed to resolve the selected Xcode toolchain via xcode-select; pass --toolchain-path explicitly")
  }

  let developerDirectory = output.trimmingCharacters(in: .whitespacesAndNewlines)
  return (developerDirectory as NSString).appendingPathComponent("Toolchains/XcodeDefault.xctoolchain")
}

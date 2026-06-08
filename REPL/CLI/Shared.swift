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

  @Option(name: .long, help: "Path to the Swift module for the test target. Must end with a .swiftmodule file.")
  var swiftModule: String

  @Option(name: .long, help: "Path to the explicit Swift module map for the test target. Must end with a .json file.")
  var swiftModuleMap: String

  func validate() throws {
    guard (swiftModule as NSString).pathExtension == "swiftmodule" else {
      throw ValidationError("--swift-module path must end with a .swiftmodule file, got: \(swiftModule)")
    }
    guard (swiftModuleMap as NSString).pathExtension == "json" else {
      throw ValidationError("--swift-module-map path must end with a .json file, got: \(swiftModuleMap)")
    }
  }
}

class SessionDirectory {
  let path: String
  private var created = false

  init() {
    path = (NSTemporaryDirectory() as NSString)
      .appendingPathComponent("idb_repl_\(UUID().uuidString)")
  }

  deinit {
    cleanup()
  }

  func filePath(named name: String) throws -> String {
    if !created {
      try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
      created = true
    }
    return (path as NSString).appendingPathComponent(name)
  }

  func cleanup() {
    if created {
      try? FileManager.default.removeItem(atPath: path)
      created = false
    }
  }
}

let sessionDirectory = SessionDirectory()

enum Platform: String, ExpressibleByArgument, CaseIterable {
  case ios
  case macos

  var sdkName: String {
    switch self {
    case .ios: return "iphonesimulator"
    case .macos: return "macosx"
    }
  }

  func targetTriple(version: String) -> String {
    switch self {
    case .ios: return "arm64-apple-ios\(version)-simulator"
    case .macos: return "arm64-apple-macosx\(version)"
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

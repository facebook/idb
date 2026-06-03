/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import ArgumentParser
import Foundation

struct SharedOptions: ParsableArguments {
  @Option(name: .long, help: "Simulator identifier.")
  var udid: String

  @Option(name: .long, help: "Path to a custom Simulator device set.")
  var deviceSetPath: String?

  @Option(name: .long, help: "Path to the idb-xctest .app bundle.")
  var idbXctestPath: String

  @Option(name: .long, help: "Path to the test bundle.")
  var testBundlePath: String
}

class SessionDirectory {
  let path: String
  private var created = false

  init() {
    path = (NSTemporaryDirectory() as NSString)
      .appendingPathComponent("test_repl_\(UUID().uuidString)")
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

func launchAndWaitForPid(options: SharedOptions) throws -> (Process, Int32) {
  var arguments = [
    "ios", "repl", "logic",
    "--bundle-path", options.testBundlePath,
    "--udid", options.udid,
  ]

  if let deviceSetPath = options.deviceSetPath {
    arguments += ["--device-set-path", deviceSetPath]
  }

  guard let appBundle = Bundle(path: options.idbXctestPath),
    let executableURL = appBundle.executableURL
  else {
    throw ValidationError("Failed to load app bundle or find executable at '\(options.idbXctestPath)'")
  }

  let process = Process()
  process.executableURL = executableURL
  process.arguments = arguments

  process.standardInput = FileHandle.nullDevice
  let pipe = Pipe()
  process.standardOutput = pipe

  try process.run()

  let fileHandle = pipe.fileHandleForReading

  while process.isRunning {
    guard let line = readLine(from: fileHandle) else {
      continue
    }

    if let testPid = parsePid(from: line) {
      return (process, testPid)
    }
  }

  throw ValidationError("idb-xctest exited without reporting a PID")
}

func sendCommand(_ command: String, to writeHandle: FileHandle, readingFrom readHandle: FileHandle? = nil) {
  writeHandle.write(Data((command + "\n").utf8))
  if let readHandle {
    _ = readLine(from: readHandle)
  }
}

func readLine(from fileHandle: FileHandle) -> String? {
  var lineData = Data()
  while true {
    let byte = fileHandle.readData(ofLength: 1)
    if byte.isEmpty {
      return lineData.isEmpty ? nil : String(data: lineData, encoding: .utf8)
    }
    if byte[0] == 0x0A {
      return String(data: lineData, encoding: .utf8)
    }
    lineData.append(byte)
  }
}

func parsePid(from line: String) -> Int32? {
  guard let data = line.data(using: .utf8),
    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
    let pid = json["pid"] as? Int32
  else {
    return nil
  }
  return pid
}

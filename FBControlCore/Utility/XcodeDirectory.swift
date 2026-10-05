/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

enum XcodeDirectoryError: Error, LocalizedError {
  case xcodeSelectTimedOut
  case xcodeSelectFailed(status: Int32, stdErr: String)
  case emptyXcodeSelectOutput(stdErr: String)
  case pathNil
  case commandLineToolsOnly
  case rootPath
  case pathDoesNotExist(directory: String)

  public var errorDescription: String? {
    switch self {
    case .xcodeSelectTimedOut:
      return "`xcode-select -p` did not return the developer directory within 10 seconds."
    case let .xcodeSelectFailed(status, stdErr):
      return "`xcode-select -p` failed with status \(status): \(stdErr)"
    case let .emptyXcodeSelectOutput(stdErr):
      return "Empty output for xcode directory returned from `xcode-select -p`: \(stdErr)"
    case .pathNil:
      return "Xcode path is nil"
    case .commandLineToolsOnly:
      return "`xcode-select -p` returned '/Library/Developer/CommandLineTools', but idb requires a full Xcode install."
    case .rootPath:
      return "`xcode-select -p` returned '/' which isn't valid."
    case let .pathDoesNotExist(directory):
      return "`xcode-select -p` returned '\(directory)' which doesn't exist."
    }
  }
}

struct XcodeDirectory {

  public static func resolveDeveloperDirectory() throws -> String {
    let directory: String
    do {
      directory = try symlinkedDeveloperDirectory()
    } catch {
      directory = try xcodeSelectDeveloperDirectory()
    }
    return directory
  }

  public static func xcodeSelectDeveloperDirectory() throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
    process.arguments = ["--print-path"]
    let stdOutPipe = Pipe()
    let stdErrPipe = Pipe()
    process.standardOutput = stdOutPipe
    process.standardError = stdErrPipe
    let exited = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in exited.signal() }
    try process.run()
    guard exited.wait(timeout: .now() + 10) == .success else {
      process.terminate()
      throw XcodeDirectoryError.xcodeSelectTimedOut
    }
    // The output is a single path, well within the pipe buffer, so it can be read after exit.
    let stdErr = String(decoding: stdErrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    guard process.terminationStatus == 0 else {
      throw XcodeDirectoryError.xcodeSelectFailed(status: process.terminationStatus, stdErr: stdErr)
    }
    let directory = String(decoding: stdOutPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if directory.isEmpty {
      throw XcodeDirectoryError.emptyXcodeSelectOutput(stdErr: stdErr)
    }
    let resolved = (directory as NSString).resolvingSymlinksInPath
    try validateXcodeDirectory(resolved)
    return resolved
  }

  public static func symlinkedDeveloperDirectory() throws -> String {
    let directory: String = ("/var/db/xcode_select_link" as NSString).resolvingSymlinksInPath
    try validateXcodeDirectory(directory)
    return directory
  }

  private static func validateXcodeDirectory(_ directory: String?) throws {
    guard let directory else {
      throw XcodeDirectoryError.pathNil
    }
    guard directory != "/Library/Developer/CommandLineTools" else {
      throw XcodeDirectoryError.commandLineToolsOnly
    }
    guard directory != "/" else {
      throw XcodeDirectoryError.rootPath
    }
    guard FileManager.default.fileExists(atPath: directory) else {
      throw XcodeDirectoryError.pathDoesNotExist(directory: directory)
    }
  }
}

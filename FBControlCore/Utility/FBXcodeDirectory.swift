/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// The ways developer-directory resolution can fail, as data rather than assembled strings.
public enum FBXcodeDirectoryError: Error, LocalizedError {
  case emptyXcodeSelectOutput(stdErr: String)
  case pathNil
  case commandLineToolsOnly
  case rootPath
  case pathDoesNotExist(directory: String)

  public var errorDescription: String? {
    switch self {
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

public struct FBXcodeDirectory {

  // MARK: Public

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
    let timedFuture = FBProcessBuilder<AnyObject, AnyObject, AnyObject>
      .withLaunchPath("/usr/bin/xcode-select", arguments: ["--print-path"])
      .withStdOutInMemoryAsString()
      .withStdErrInMemoryAsString()
      .runUntilCompletion(withAcceptableExitCodes: Set([0 as NSNumber]))
      .timeout(10, waitingFor: "xcode-select to return the developer directory")
    let taskObj = try timedFuture.await()
    // swiftlint:disable:next force_cast
    let task = taskObj as! FBSubprocess<AnyObject, AnyObject, AnyObject>
    let directory = task.stdOut as? String ?? ""
    if directory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      let stdErr = task.stdErr as? String ?? ""
      throw FBXcodeDirectoryError.emptyXcodeSelectOutput(stdErr: stdErr)
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

  // MARK: Private

  private static func validateXcodeDirectory(_ directory: String?) throws {
    guard let directory else {
      throw FBXcodeDirectoryError.pathNil
    }
    guard directory != "/Library/Developer/CommandLineTools" else {
      throw FBXcodeDirectoryError.commandLineToolsOnly
    }
    guard directory != "/" else {
      throw FBXcodeDirectoryError.rootPath
    }
    guard FileManager.default.fileExists(atPath: directory) else {
      throw FBXcodeDirectoryError.pathDoesNotExist(directory: directory)
    }
  }
}

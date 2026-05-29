/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

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
      throw
        FBControlCoreError
        .describe("Empty output for xcode directory returned from `xcode-select -p`: \(stdErr)")
        .build()
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
      throw
        FBControlCoreError
        .describe("Xcode path is nil")
        .build()
    }
    guard directory != "/Library/Developer/CommandLineTools" else {
      throw
        FBControlCoreError
        .describe("`xcode-select -p` returned '/Library/Developer/CommandLineTools', but idb requires a full Xcode install.")
        .build()
    }
    guard directory != "/" else {
      throw
        FBControlCoreError
        .describe("`xcode-select -p` returned '/' which isn't valid.")
        .build()
    }
    guard FileManager.default.fileExists(atPath: directory) else {
      throw
        FBControlCoreError
        .describe("`xcode-select -p` returned '\(directory)' which doesn't exist.")
        .build()
    }
  }
}

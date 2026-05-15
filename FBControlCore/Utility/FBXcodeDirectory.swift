/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

private let HelpText = """
  .

  ============================
  Please make sure xcode is installed and then run:
  sudo xcode-select -s $(ls -td /Applications/Xcode* | head -1)/Contents/Developer
  ============================

  .
  """

@objc(FBXcodeDirectory)
public final class FBXcodeDirectory: NSObject {

  // MARK: Public Methods

  @objc public class func xcodeSelectDeveloperDirectory() -> FBFuture<NSString> {
    let queue = DispatchQueue.global(qos: .userInitiated)

    return FBProcessBuilder<AnyObject, AnyObject, AnyObject>
      .withLaunchPath("/usr/bin/xcode-select", arguments: ["--print-path"])
      .withStdOutInMemoryAsString()
      .withStdErrInMemoryAsString()
      .runUntilCompletion(withAcceptableExitCodes: Set([0 as NSNumber]))
      .timeout(10, waitingFor: "xcode-select to return the developer directory")
      .onQueue(
        queue,
        fmap: { taskObj -> FBFuture<AnyObject> in
          let task = taskObj as! FBSubprocess<AnyObject, AnyObject, AnyObject>
          let directory = task.stdOut as? String ?? ""
          if directory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let stdErr = task.stdErr as? String ?? ""
            return
              FBControlCoreError
              .describe("Empty output for xcode directory returned from `xcode-select -p`: \(stdErr)\(HelpText)")
              .failFuture()
          }
          let resolved = (directory as NSString).resolvingSymlinksInPath

          do {
            try Self.validateXcodeDirectory(resolved)
          } catch {
            return FBFuture<AnyObject>(error: error)
          }
          return FBFuture<AnyObject>(result: resolved as NSString)
        }) as! FBFuture<NSString>
  }

  @objc public class func symlinkedDeveloperDirectory() throws -> String {
    let directory = ("/var/db/xcode_select_link" as NSString).resolvingSymlinksInPath
    try validateXcodeDirectory(directory)
    return directory
  }

  // MARK: Private

  private class func validateXcodeDirectory(_ directory: String?) throws {
    guard let directory else {
      throw
        FBControlCoreError
        .describe("Xcode Path is nil")
        .build()
    }
    if directory == "/Library/Developer/CommandLineTools" {
      throw
        FBControlCoreError
        .describe("`xcode-select -p` returned /Library/Developer/CommandLineTools but idb requires a full xcode install.\(HelpText)")
        .build()
    }
    if !FileManager.default.fileExists(atPath: directory) {
      throw
        FBControlCoreError
        .describe("`xcode-select -p` returned \(directory) which doesn't exist\(HelpText)")
        .build()
    }
    if directory == "/" {
      throw
        FBControlCoreError
        .describe("`xcode-select -p` returned / which isn't valid.\(HelpText)")
        .build()
    }
  }
}

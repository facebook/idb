/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// The ways codesigning can fail, as data rather than assembled strings.
public enum FBCodesignError: Error, LocalizedError {
  case signingFailed(exitCode: NSNumber, stdOut: String, stdErr: String)
  case cdHashCheckFailed(exitCode: NSNumber, stdOut: String, stdErr: String)
  case cdHashNotFound(output: String)

  public var errorDescription: String? {
    switch self {
    case let .signingFailed(exitCode, stdOut, stdErr):
      return "Codesigning failed with exit code \(exitCode), \(stdOut)\n\(stdErr)"
    case let .cdHashCheckFailed(exitCode, stdOut, stdErr):
      return "Checking CDHash of codesign execution failed \(exitCode), \(stdOut)\n\(stdErr)"
    case let .cdHashNotFound(output):
      return "Could not find 'CDHash' in output: \(output)"
    }
  }
}

public class FBCodesignProvider: NSObject {

  // MARK: Properties

  public let identityName: String
  private let logger: FBControlCoreLogger?
  private let queue: DispatchQueue

  // MARK: Initializers

  public class func codeSignCommand(withIdentityName identityName: String, logger: FBControlCoreLogger?) -> Self {
    self.init(identityName: identityName, logger: logger)
  }

  public class func codeSignCommandWithAdHocIdentity(logger: FBControlCoreLogger?) -> Self {
    self.init(identityName: "-", logger: logger)
  }

  required init(identityName: String, logger: FBControlCoreLogger?) {
    self.identityName = identityName
    self.logger = logger
    self.queue = DispatchQueue(label: "com.facebook.fbcontrolcore.codesign", attributes: .concurrent)
    super.init()
  }

  // MARK: Private

  private func makeCodesignatureWritable(_ bundlePath: String) throws {
    let fileManager = FileManager.default
    let codeSignatureFile = bundlePath + "/_CodeSignature/CodeResources"
    guard fileManager.fileExists(atPath: codeSignatureFile) else {
      return
    }
    guard !fileManager.isWritableFile(atPath: codeSignatureFile) else {
      return
    }
    var attributes = try fileManager.attributesOfItem(atPath: codeSignatureFile)
    if let posixPermissions = attributes[.posixPermissions] as? NSNumber {
      let currentPermissions = posixPermissions.int16Value
      let newPermissions = currentPermissions | 0b010000000
      attributes[.posixPermissions] = NSNumber(value: newPermissions)
      try fileManager.setAttributes(attributes, ofItemAtPath: codeSignatureFile)
      logger?.log("Added user writable permission to code sign file")
    }
  }

  // MARK: Public Methods

  public func signBundle(atPath bundlePath: String) -> FBFuture<NSNull> {
    do {
      try makeCodesignatureWritable(bundlePath)
    } catch {
      return FBFuture(error: error as NSError)
    }
    logger?.log("Signing bundle \(bundlePath) with identity \(identityName)")

    return unsafeBitCast(
      FBProcessBuilder<AnyObject, AnyObject, AnyObject>
        .withLaunchPath("/usr/bin/codesign", arguments: ["-s", identityName, "-f", bundlePath])
        .withStdOutInMemoryAsString()
        .withStdErrInMemoryAsString()
        .withTaskLifecycleLogging(to: logger)
        .runUntilCompletion(withAcceptableExitCodes: nil)
        .onQueue(
          queue,
          fmap: { [logger] task -> FBFuture<AnyObject> in
            let exitCode = task.exitCode.result
            if exitCode != 0 {
              return FBFuture(error: FBCodesignError.signingFailed(exitCode: exitCode ?? -1, stdOut: (task.stdOut as String?) ?? "", stdErr: (task.stdErr as String?) ?? ""))
            }
            logger?.log("Successfully signed bundle \(task.stdErr ?? "")")
            return FBFuture<AnyObject>(result: NSNull())
          }),
      to: FBFuture<NSNull>.self
    )
  }

  public func recursivelySignBundle(atPath bundlePath: String) -> FBFuture<NSNull> {
    var pathsToSign = [bundlePath]
    let fileManager = FileManager.default
    let frameworksPath = bundlePath + "/Frameworks/"
    if fileManager.fileExists(atPath: frameworksPath) {
      do {
        let frameworkNames = try fileManager.contentsOfDirectory(atPath: frameworksPath)
        for frameworkPath in frameworkNames {
          pathsToSign.append(frameworksPath + frameworkPath)
        }
      } catch {
        return FBFuture(error: error)
      }
    }
    var futures: [FBFuture<AnyObject>] = []
    for pathToSign in pathsToSign {
      futures.append(unsafeBitCast(signBundle(atPath: pathToSign), to: FBFuture<AnyObject>.self))
    }
    return unsafeBitCast(
      FBFuture<AnyObject>.combine(futures).mapReplace(NSNull()),
      to: FBFuture<NSNull>.self
    )
  }

  public func cdHashForBundle(atPath bundlePath: String) -> FBFuture<NSString> {
    logger?.log("Obtaining CDHash for bundle at path \(bundlePath)")
    return unsafeBitCast(
      FBProcessBuilder<AnyObject, AnyObject, AnyObject>
        .withLaunchPath("/usr/bin/codesign", arguments: ["-dvvvv", bundlePath])
        .withStdOutInMemoryAsString()
        .withStdErrInMemoryAsString()
        .withTaskLifecycleLogging(to: logger)
        .runUntilCompletion(withAcceptableExitCodes: nil)
        .onQueue(
          queue,
          fmap: { [logger] task -> FBFuture<AnyObject> in
            let exitCode = task.exitCode.result
            if exitCode != 0 {
              return FBFuture(error: FBCodesignError.cdHashCheckFailed(exitCode: exitCode ?? -1, stdOut: (task.stdOut as String?) ?? "", stdErr: (task.stdErr as String?) ?? ""))
            }
            let output = (task.stdErr ?? "") as String
            guard let result = output.firstMatch(of: /CDHash=(.+)/) else {
              return FBFuture(error: FBCodesignError.cdHashNotFound(output: output))
            }
            let cdHash = String(result.1)
            logger?.log("Successfully obtained hash \(cdHash) from bundle \(bundlePath)")
            return FBFuture<AnyObject>(result: cdHash as NSString)
          }),
      to: FBFuture<NSString>.self
    )
  }
}

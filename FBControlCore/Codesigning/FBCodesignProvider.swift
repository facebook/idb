/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Helper to call [FBFuture futureWithFutures:] which is NS_SWIFT_UNAVAILABLE.
private func combineFutures(_ futures: [FBFuture<AnyObject>]) -> FBFuture<AnyObject> {
  let sel = NSSelectorFromString("futureWithFutures:")
  let method = FBFuture<AnyObject>.method(for: sel)
  typealias Signature = @convention(c) (AnyObject, Selector, NSArray) -> FBFuture<AnyObject>
  let impl = unsafeBitCast(method, to: Signature.self)
  return impl(FBFuture<AnyObject>.self, sel, futures as NSArray)
}

@objc(FBCodesignProvider)
public class FBCodesignProvider: NSObject {

  // MARK: Properties

  @objc public let identityName: String
  private let logger: FBControlCoreLogger?
  private let queue: DispatchQueue

  // MARK: Initializers

  @objc(codeSignCommandWithIdentityName:logger:)
  public class func codeSignCommand(withIdentityName identityName: String, logger: FBControlCoreLogger?) -> Self {
    return self.init(identityName: identityName, logger: logger)
  }

  @objc(codeSignCommandWithAdHocIdentityWithLogger:)
  public class func codeSignCommandWithAdHocIdentity(logger: FBControlCoreLogger?) -> Self {
    return self.init(identityName: "-", logger: logger)
  }

  required init(identityName: String, logger: FBControlCoreLogger?) {
    self.identityName = identityName
    self.logger = logger
    self.queue = DispatchQueue(label: "com.facebook.fbcontrolcore.codesign", attributes: .concurrent)
    super.init()
  }

  // MARK: Private

  private static let cdHashRegex: NSRegularExpression = {
    // swiftlint:disable:next force_try
    return try! NSRegularExpression(pattern: "CDHash=(.+)", options: [])
  }()

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
    let currentPermissions = (attributes[.posixPermissions] as! NSNumber).int16Value
    let newPermissions = currentPermissions | 0b010000000
    attributes[.posixPermissions] = NSNumber(value: newPermissions)
    try fileManager.setAttributes(attributes, ofItemAtPath: codeSignatureFile)
    logger?.log("Added user writable permission to code sign file")
  }

  // MARK: Public Methods

  @objc(signBundleAtPath:)
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
          fmap: { [logger] (taskObj: AnyObject) -> FBFuture<AnyObject> in
            let task = taskObj as! FBSubprocess<NSNull, NSString, NSString>
            let exitCode = task.exitCode.result
            if exitCode != 0 {
              return
                FBControlCoreError
                .describe("Codesigning failed with exit code \(exitCode ?? -1), \(task.stdOut ?? "")\n\(task.stdErr ?? "")")
                .failFuture()
            }
            logger?.log("Successfully signed bundle \(task.stdErr ?? "")")
            return FBFuture<AnyObject>(result: NSNull())
          }),
      to: FBFuture<NSNull>.self
    )
  }

  @objc(recursivelySignBundleAtPath:)
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
        return unsafeBitCast(
          FBControlCoreError.failFuture(with: error as NSError),
          to: FBFuture<NSNull>.self
        )
      }
    }
    var futures: [FBFuture<AnyObject>] = []
    for pathToSign in pathsToSign {
      futures.append(unsafeBitCast(signBundle(atPath: pathToSign), to: FBFuture<AnyObject>.self))
    }
    return unsafeBitCast(
      combineFutures(futures).mapReplace(NSNull()),
      to: FBFuture<NSNull>.self
    )
  }

  @objc(cdHashForBundleAtPath:)
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
          fmap: { [logger] (taskObj: AnyObject) -> FBFuture<AnyObject> in
            let task = taskObj as! FBSubprocess<NSNull, NSString, NSString>
            let exitCode = task.exitCode.result
            if exitCode != 0 {
              return
                FBControlCoreError
                .describe("Checking CDHash of codesign execution failed \(exitCode ?? -1), \(task.stdOut ?? "")\n\(task.stdErr ?? "")")
                .failFuture()
            }
            let output = (task.stdErr ?? "") as String
            guard let result = FBCodesignProvider.cdHashRegex.firstMatch(in: output, options: [], range: NSRange(location: 0, length: output.count)) else {
              return
                FBControlCoreError
                .describe("Could not find 'CDHash' in output: \(output)")
                .failFuture()
            }
            let cdHash = (output as NSString).substring(with: result.range(at: 1))
            logger?.log("Successfully obtained hash \(cdHash) from bundle \(bundlePath)")
            return FBFuture<AnyObject>(result: cdHash as NSString)
          }),
      to: FBFuture<NSString>.self
    )
  }
}

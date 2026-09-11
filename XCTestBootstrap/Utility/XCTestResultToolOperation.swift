/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

private let XcrunPath = "/usr/bin/xcrun"
private let SipsPath = "/usr/bin/sips"
private let HEIC = "public.heic"
private let JPEG = "public.jpeg"

enum XCTestResultToolError: Error, LocalizedError {
  case unrecognizedScreenshotEncoding(encoding: String)

  public var errorDescription: String? {
    switch self {
    case let .unrecognizedScreenshotEncoding(encoding):
      return "Unrecognized XCTest screenshot encoding: \(encoding)"
    }
  }
}

final class XCTestResultToolOperation {

  private static func runProcess(launchPath: String, arguments: [String], logger: FBControlCoreLogger?) -> FBFuture<AnyObject> {
    let base = FBProcessBuilder<NSNull, NSData, NSData>.withLaunchPath(launchPath, arguments: arguments).withTaskLifecycleLogging(to: logger)
    if let logger {
      let withStdErr = base.withStdErr(to: logger)
      return withStdErr.runUntilCompletion(withAcceptableExitCodes: [0]).retyped(FBFuture<AnyObject>.self)
    } else {
      return base.runUntilCompletion(withAcceptableExitCodes: [0]).retyped(FBFuture<AnyObject>.self)
    }
  }

  private static func internalOperation(withArguments arguments: [String], queue: DispatchQueue, logger: FBControlCoreLogger?) -> FBFuture<FBSubprocess<AnyObject, AnyObject, AnyObject>> {
    let xcrunArguments = ["xcresulttool"] + arguments
    return
      XCTestResultToolOperation.runProcess(launchPath: XcrunPath, arguments: xcrunArguments, logger: logger)
      .onQueue(
        queue,
        map: { task -> AnyObject in
          task
        }
      )
      .retyped(FBFuture<FBSubprocess<AnyObject, AnyObject, AnyObject>>.self)
  }

  private static func exportFrom(_ path: String, to destination: String, forId bundleObjectId: String, withType exportType: String, queue: DispatchQueue, logger: FBControlCoreLogger?) -> FBFuture<FBSubprocess<AnyObject, AnyObject, AnyObject>> {
    let arguments = ["export", "--path", path, "--output-path", destination, "--id", bundleObjectId, "--type", exportType]
    return XCTestResultToolOperation.internalOperation(withArguments: arguments, queue: queue, logger: logger)
  }

  private static func getJSON(fromTask task: FBSubprocess<AnyObject, AnyObject, AnyObject>) -> NSDictionary {
    guard let stdOut = task.stdOut as? NSString,
      let data = stdOut.data(using: String.Encoding.utf8.rawValue)
    else {
      return NSDictionary()
    }
    return (try? JSONSerialization.jsonObject(with: data, options: [])) as? NSDictionary ?? NSDictionary()
  }

  public static func getJSON(from path: String, forId bundleObjectId: String?, queue: DispatchQueue, logger: FBControlCoreLogger?) -> FBFuture<NSDictionary> {
    logger?.log("Getting json for id \(bundleObjectId ?? "nil")")
    var arguments = ["get", "--path", path, "--format", "json"]
    if let bundleObjectId, !bundleObjectId.isEmpty {
      arguments.append(contentsOf: ["--id", bundleObjectId])
    }
    return
      XCTestResultToolOperation.internalOperation(withArguments: arguments, queue: queue, logger: logger)
      .onQueue(
        queue,
        map: { subprocess -> AnyObject in
          XCTestResultToolOperation.getJSON(fromTask: subprocess)
        }
      )
      .retyped(FBFuture<NSDictionary>.self)
  }

  public static func exportFile(from path: String, to destination: String, forId bundleObjectId: String, queue: DispatchQueue, logger: FBControlCoreLogger?) -> FBFuture<FBSubprocess<AnyObject, AnyObject, AnyObject>> {
    return XCTestResultToolOperation.exportFrom(path, to: destination, forId: bundleObjectId, withType: "file", queue: queue, logger: logger)
  }

  public static func exportJPEG(from path: String, to destination: String, forId bundleObjectId: String, type encodeType: String, queue: DispatchQueue, logger: FBControlCoreLogger?) -> FBFuture<FBSubprocess<AnyObject, AnyObject, AnyObject>> {
    return
      XCTestResultToolOperation.exportFile(from: path, to: destination, forId: bundleObjectId, queue: queue, logger: logger)
      .retyped(FBFuture<AnyObject>.self)
      .onQueue(
        queue,
        fmap: { task -> FBFuture<AnyObject> in
          if encodeType == HEIC {
            return XCTestResultToolOperation.runProcess(launchPath: SipsPath, arguments: ["-s", "format", "jpeg", destination, "--out", destination], logger: logger)
          } else if encodeType == JPEG {
            return FBFuture(result: task)
          } else {
            return FBFuture(error: XCTestResultToolError.unrecognizedScreenshotEncoding(encoding: String(describing: encodeType)))
          }
        }
      )
      .retyped(FBFuture<FBSubprocess<AnyObject, AnyObject, AnyObject>>.self)
  }

  public static func exportDirectory(from path: String, to destination: String, forId bundleObjectId: String, queue: DispatchQueue, logger: FBControlCoreLogger?) -> FBFuture<FBSubprocess<AnyObject, AnyObject, AnyObject>> {
    return XCTestResultToolOperation.exportFrom(path, to: destination, forId: bundleObjectId, withType: "directory", queue: queue, logger: logger)
  }

  public static func describeFormat(_ queue: DispatchQueue, logger: FBControlCoreLogger?) -> FBFuture<NSDictionary> {
    let arguments = ["formatDescription"]
    return
      XCTestResultToolOperation.internalOperation(withArguments: arguments, queue: queue, logger: logger)
      .onQueue(
        queue,
        map: { subprocess -> AnyObject in
          XCTestResultToolOperation.getJSON(fromTask: subprocess)
        }
      )
      .retyped(FBFuture<NSDictionary>.self)
  }
}

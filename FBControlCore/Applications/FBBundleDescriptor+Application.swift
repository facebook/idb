/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

extension FBBundleDescriptor {

  @objc(findAppPathFromDirectory:logger:error:)
  public class func findAppPath(fromDirectory directory: URL, logger: FBControlCoreLogger?) throws -> FBBundleDescriptor {
    let directoryEnumerator = FileManager.default.enumerator(
      at: directory,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [],
      errorHandler: nil
    )
    var applicationPaths: [String] = []
    var nonApplicationPaths: [String] = []
    logger?.log("Finding Application Path from root directory \(directory)")
    if let enumerator = directoryEnumerator {
      for case let fileURL as URL in enumerator {
        let path = fileURL.path
        if FBBundleDescriptor.isApplication(atPath: path) {
          logger?.log("Found application at path \(path)")
          applicationPaths.append(path)
          enumerator.skipDescendants()
        } else {
          logger?.log("Non-application path at \(path)")
          nonApplicationPaths.append(path)
        }
      }
    }
    if applicationPaths.isEmpty {
      let lastComponents = nonApplicationPaths.map { ($0 as NSString).lastPathComponent }
      throw FBControlCoreError
        .describe("Could not find an Application in IPA, present files \(FBCollectionInformation.oneLineDescription(from: lastComponents))")
        .build()
    }
    if applicationPaths.count > 1 {
      let lastComponents = applicationPaths.map { ($0 as NSString).lastPathComponent }
      throw FBControlCoreError
        .describe("Expected only one Application in IPA, found \(applicationPaths.count): \(FBCollectionInformation.oneLineDescription(from: lastComponents))")
        .build()
    }
    let applicationPath = applicationPaths[0]
    logger?.log("Using Application at path \(applicationPath)")
    let bundle = try FBBundleDescriptor.bundle(fromPath: applicationPath)
    logger?.log("Bundle in IPA is \(bundle)")
    return bundle
  }

  @objc(isApplicationAtPath:)
  public class func isApplication(atPath path: String) -> Bool {
    var isDirectory: ObjCBool = false
    return path.hasSuffix(".app")
      && FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
      && isDirectory.boolValue
  }
}

/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import XCTestBootstrap

@objc public final class FBXCTestRunFileReader: NSObject {

  @objc public static func readContents(of xctestrunURL: URL, expandPlaceholderWithPath path: String) throws -> [String: Any] {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: xctestrunURL.path) else {
      throw FBXCTestError.describe("xctestrun file does not exist at expected location: \(xctestrunURL)").build()
    }
    let testRoot = (xctestrunURL.path as NSString).deletingLastPathComponent
    let idbAppStoragePath = (path as NSString).appendingPathComponent(IdbApplicationsFolder)
    guard fileManager.fileExists(atPath: idbAppStoragePath) else {
      throw FBXCTestError.describe("IDB app storage folder does not exist at: \(idbAppStoragePath)").build()
    }
    guard let xctestrunContents = try? NSDictionary(contentsOf: xctestrunURL, error: ()) as? [String: Any] else {
      throw FBXCTestError.describe("Failed to read xctestrun file at \(xctestrunURL)").build()
    }
    var mutableContents: [String: Any] = [:]
    for contentKey in xctestrunContents.keys {
      if contentKey == "__xctestrun_metadata__" || contentKey == "CodeCoverageBuildableInfos" {
        mutableContents[contentKey] = xctestrunContents[contentKey]
        continue
      }
      guard var testTargetProperties = (xctestrunContents[contentKey] as? [String: Any])?.asMutable() else {
        continue
      }
      // Expand __TESTROOT__ and __IDB_APPSTORAGE__ in TestHostPath
      if var testHostPath = testTargetProperties["TestHostPath"] as? String {
        testHostPath = testHostPath.replacingOccurrences(of: "__TESTROOT__", with: testRoot)
        testHostPath = testHostPath.replacingOccurrences(of: "__IDB_APPSTORAGE__", with: idbAppStoragePath)
        testTargetProperties["TestHostPath"] = testHostPath

        // Expand __TESTROOT__ and __TESTHOST__ in TestBundlePath
        if var testBundlePath = testTargetProperties["TestBundlePath"] as? String {
          testBundlePath = testBundlePath.replacingOccurrences(of: "__TESTROOT__", with: testRoot)
          testBundlePath = testBundlePath.replacingOccurrences(of: "__TESTHOST__", with: testHostPath)
          testTargetProperties["TestBundlePath"] = testBundlePath
        }
      }
      // Expand __IDB_APPSTORAGE__ in UITargetAppPath
      if var targetAppPath = testTargetProperties["UITargetAppPath"] as? String {
        targetAppPath = targetAppPath.replacingOccurrences(of: "__IDB_APPSTORAGE__", with: idbAppStoragePath)
        targetAppPath = targetAppPath.replacingOccurrences(of: "__TESTROOT__", with: testRoot)
        testTargetProperties["UITargetAppPath"] = targetAppPath
      }
      if let dependencies = testTargetProperties["DependentProductPaths"] as? [String], !dependencies.isEmpty {
        let expandedDeps = dependencies.map { dep -> String in
          var absPath = dep.replacingOccurrences(of: "__IDB_APPSTORAGE__", with: idbAppStoragePath)
          absPath = absPath.replacingOccurrences(of: "__TESTROOT__", with: testRoot)
          return absPath
        }
        testTargetProperties["DependentProductPaths"] = expandedDeps
      }
      mutableContents[contentKey] = testTargetProperties
    }
    return mutableContents
  }
}

private extension Dictionary where Key == String, Value == Any {
  func asMutable() -> [String: Any] {
    let copy = self
    return copy
  }
}

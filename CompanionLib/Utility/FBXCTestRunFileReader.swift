/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import XCTestBootstrap

public enum FBXCTestRunFileError: Error {
  case fileMissing(url: URL)
  case appStorageMissing(path: String)
  case fileUnreadable(url: URL)
}

extension FBXCTestRunFileError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .fileMissing(url):
      return "xctestrun file does not exist at expected location: \(url)"
    case let .appStorageMissing(path):
      return "IDB app storage folder does not exist at: \(path)"
    case let .fileUnreadable(url):
      return "Failed to read xctestrun file at \(url)"
    }
  }
}

public final class FBXCTestRunFileReader {

  public static func readContents(of xctestrunURL: URL, expandPlaceholderWithPath path: String) throws -> [String: Any] {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: xctestrunURL.path) else {
      throw FBXCTestRunFileError.fileMissing(url: xctestrunURL)
    }
    let testRoot = (xctestrunURL.path as NSString).deletingLastPathComponent
    let idbAppStoragePath = (path as NSString).appendingPathComponent(IdbApplicationsFolder)
    guard fileManager.fileExists(atPath: idbAppStoragePath) else {
      throw FBXCTestRunFileError.appStorageMissing(path: idbAppStoragePath)
    }
    guard let xctestrunContents = try NSDictionary(contentsOf: xctestrunURL, error: ()) as? [String: Any] else {
      throw FBXCTestRunFileError.fileUnreadable(url: xctestrunURL)
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
      if var testHostPath = testTargetProperties["TestHostPath"] as? String {
        testHostPath = testHostPath.replacingOccurrences(of: "__TESTROOT__", with: testRoot)
        testHostPath = testHostPath.replacingOccurrences(of: "__IDB_APPSTORAGE__", with: idbAppStoragePath)
        testTargetProperties["TestHostPath"] = testHostPath

        if var testBundlePath = testTargetProperties["TestBundlePath"] as? String {
          testBundlePath = testBundlePath.replacingOccurrences(of: "__TESTROOT__", with: testRoot)
          testBundlePath = testBundlePath.replacingOccurrences(of: "__TESTHOST__", with: testHostPath)
          testTargetProperties["TestBundlePath"] = testBundlePath
        }
      }
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

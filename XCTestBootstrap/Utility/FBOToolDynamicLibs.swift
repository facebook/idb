/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

enum FBOToolDynamicLibsError: Error {
  case directoryListFailed(path: String, underlying: Error)
  case clangVersionNotFound(path: String)
}

extension FBOToolDynamicLibsError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .directoryListFailed(path, _):
      return "Failed to list files in directory \(path)"
    case let .clangVersionNotFound(path):
      return "No clang version found in \(path)"
    }
  }
}

final class FBOToolDynamicLibs {

  public static func findFullPath(forSanitiserDyldInBundle bundlePath: String) async throws -> [String] {
    let libsList = try await FBOToolOperation.listSanitiserDylibsRequired(byBundle: bundlePath)

    let clangLocation = (FBXcodeConfiguration.developerDirectory as NSString).appendingPathComponent("Toolchains/XcodeDefault.xctoolchain/usr/lib/clang")
    let fileList: [URL]
    do {
      fileList = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: clangLocation), includingPropertiesForKeys: [.isDirectoryKey], options: [])
    } catch {
      throw FBOToolDynamicLibsError.directoryListFailed(path: clangLocation, underlying: error)
    }

    if fileList.isEmpty {
      throw FBOToolDynamicLibsError.clangVersionNotFound(path: clangLocation)
    }

    let libsFolder = NSString.path(withComponents: [fileList[0].path, "lib/darwin/"])

    var bundleFrameworksFolder = (bundlePath as NSString).appendingPathComponent("Frameworks")
    if !FileManager.default.fileExists(atPath: bundleFrameworksFolder) {
      bundleFrameworksFolder = (bundlePath as NSString).appendingPathComponent("Contents/Frameworks")
    }

    var bundleLibsNames: Set<String>?
    if let bundleLibs = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: bundleFrameworksFolder), includingPropertiesForKeys: [.isDirectoryKey], options: []) {
      var names = Set<String>()
      for libURL in bundleLibs {
        if let libName = libURL.pathComponents.last {
          names.insert(libName)
        }
      }
      bundleLibsNames = names
    }

    var libraries: [String] = []
    for lib in libsList {
      let libPath: String
      if bundleLibsNames?.contains(lib) == true {
        libPath = (bundleFrameworksFolder as NSString).appendingPathComponent(lib)
      } else {
        libPath = (libsFolder as NSString).appendingPathComponent(lib)
      }
      libraries.append(libPath)
    }

    return libraries
  }
}

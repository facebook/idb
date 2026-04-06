/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

@objc public final class FBOToolDynamicLibs: NSObject {

  @objc public static func findFullPath(forSanitiserDyldInBundle bundlePath: String, onQueue queue: DispatchQueue) -> FBFuture<NSArray> {
    return unsafeBitCast(
      unsafeBitCast(FBOToolOperation.listSanitiserDylibsRequired(byBundle: bundlePath, onQueue: queue), to: FBFuture<AnyObject>.self)
        .onQueue(
          queue,
          fmap: { result -> FBFuture<AnyObject> in
            let libsList = result as! [String]
            let clangLocation = (FBXcodeConfiguration.developerDirectory as NSString).appendingPathComponent("Toolchains/XcodeDefault.xctoolchain/usr/lib/clang")
            let fileList: [URL]
            do {
              fileList = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: clangLocation), includingPropertiesForKeys: [.isDirectoryKey], options: [])
            } catch {
              return FBControlCoreError.describe("Failed to list files in directory \(clangLocation)").caused(by: error as NSError).failFuture()
            }

            if fileList.isEmpty {
              return FBControlCoreError.describe("No clang version found in \(clangLocation)").failFuture()
            }

            let libsFolder = NSString.path(withComponents: [fileList[0].path, "lib/darwin/"])

            var bundleFrameworksFolder = (bundlePath as NSString).appendingPathComponent("Frameworks")
            if !FileManager.default.fileExists(atPath: bundleFrameworksFolder) {
              bundleFrameworksFolder = (bundlePath as NSString).appendingPathComponent("Contents/Frameworks")
            }

            var bundleLibsNames: Set<String>?
            if let bundleLibs = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: bundleFrameworksFolder), includingPropertiesForKeys: [.isDirectoryKey], options: []) {
              bundleLibsNames = Set<String>()
              for libURL in bundleLibs {
                if let libName = libURL.pathComponents.last {
                  bundleLibsNames!.insert(libName)
                }
              }
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

            return FBFuture<AnyObject>(result: libraries as NSArray)
          }),
      to: FBFuture<NSArray>.self
    )
  }
}

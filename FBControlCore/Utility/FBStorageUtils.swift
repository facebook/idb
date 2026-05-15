/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc(FBStorageUtils)
public class FBStorageUtils: NSObject {

  // MARK: Finding Files

  @objc(bucketFilesWithExtensions:inDirectory:error:)
  public class func bucketFiles(withExtensions extensions: Set<String>, inDirectory directory: URL) throws -> [String: Set<URL>] {
    var files: [String: Set<URL>] = [:]
    for ext in extensions {
      files[ext] = Set()
    }

    let contents = try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: nil,
      options: .skipsSubdirectoryDescendants
    )

    for file in contents {
      let ext = file.pathExtension
      if extensions.contains(ext) {
        files[ext]?.insert(file)
      }
    }

    return files
  }

  @objc(findFileWithExtension:atURL:error:)
  public class func findFile(withExtension ext: String, at url: URL) throws -> URL {
    let files = try findFiles(withExtension: ext, at: url)
    if files.count != 1 {
      throw FBControlCoreError.describe("\(files.count) files with extension .\(ext) in \(url)").build()
    }
    return files.first!
  }

  @objc(findFilesWithExtension:atURL:error:)
  public class func findFiles(withExtension ext: String, at url: URL) throws -> Set<URL> {
    let buckets = try bucketFiles(withExtensions: Set([ext]), inDirectory: url)
    return buckets[ext] ?? Set()
  }

  @objc(findUniqueFileInDirectory:error:)
  public class func findUniqueFile(inDirectory directory: URL) throws -> URL {
    let filesInDirectory = try files(inDirectory: directory)
    if filesInDirectory.count != 1 {
      throw FBControlCoreError.describe("Expected one top level file, found \(filesInDirectory.count): \(FBCollectionInformation.oneLineDescription(from: filesInDirectory))").build()
    }
    return filesInDirectory[0]
  }

  @objc(filesInDirectory:error:)
  public class func files(inDirectory directory: URL) throws -> [URL] {
    do {
      return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [])
    } catch {
      throw FBControlCoreError.describe("Failed to list files in directory \(directory)").caused(by: error as NSError).build()
    }
  }

  @objc(bundleInDirectory:error:)
  public class func bundle(inDirectory directory: URL) throws -> FBBundleDescriptor {
    let uniqueFile = try findUniqueFile(inDirectory: directory)
    return try FBBundleDescriptor.bundle(fromPath: uniqueFile.path)
  }
}

/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Locates the `Resources/` directory that ships alongside the running binary and
/// holds its bundled helper tools and shims (`SimulatorFrameworkBridge`,
/// `libRepl-*.dylib`, `libShimulator-*.dylib`, `IDBAPI.swiftinterface`, `ReplHost.app`).
public struct BundledResources {

  /// The path to the bundled `Resources/` directory, or `nil` when it cannot be
  /// determined from the running bundle.
  ///
  /// Two packaging layouts are supported, each with its own resources location:
  /// - an `.app` bundle, where the resources are the bundle's own resources;
  /// - a standalone binary with a sibling `Resources/` directory next to it.
  public static func directoryPath() -> String? {
    let bundle = Bundle.main
    let bundleURL = bundle.bundleURL.standardizedFileURL
    if bundleURL.pathExtension == "app", let resourceURL = bundle.resourceURL {
      return resourceURL.path
    }
    if let executablePath = bundle.executablePath {
      let resolvedExecutablePath = (executablePath as NSString).resolvingSymlinksInPath
      let parentDirectory = (resolvedExecutablePath as NSString).deletingLastPathComponent
      return (parentDirectory as NSString).appendingPathComponent("Resources")
    }
    return nil
  }

  /// The path to `name` inside the bundled `Resources/` directory, or `nil` when
  /// the directory cannot be determined or -- when `mustExist` is `true` (the
  /// default) -- when nothing exists at that path. Pass `mustExist: false` to
  /// build the path without touching the filesystem.
  ///
  /// When the item does not exist in `Bundle.main`'s layout, every other loaded
  /// bundle's resources are consulted, so hosts that embed the frameworks and
  /// carry the resources in their own bundle (an XCTest bundle, for example)
  /// resolve them too.
  public static func path(forItem name: String, mustExist: Bool = true) -> String? {
    if let directory = directoryPath() {
      let itemPath = (directory as NSString).appendingPathComponent(name)
      if !mustExist || FileManager.default.fileExists(atPath: itemPath) {
        return itemPath
      }
    } else if !mustExist {
      return nil
    }
    for bundle in Bundle.allBundles where bundle !== Bundle.main {
      guard let resourcePath = bundle.resourcePath else {
        continue
      }
      let itemPath = (resourcePath as NSString).appendingPathComponent(name)
      if FileManager.default.fileExists(atPath: itemPath) {
        return itemPath
      }
    }
    return nil
  }
}

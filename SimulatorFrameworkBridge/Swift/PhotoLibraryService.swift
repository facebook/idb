/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import Photos

#if canImport(SimulatorFrameworkBridgeRuntime)
@_implementationOnly import SimulatorFrameworkBridgeRuntime
#endif
private func clearPhotoLibrary(client: FBPhotoLibraryClient) -> Int {
  do {
    if try client.readAssetCount().uintValue == 0 {
      NSLog("No photos to delete")
      return 0
    }
    NSLog("Found %lu photos to delete", try client.readAssetCount().uintValue)
    return client.deleteAssets() ? 0 : 1
  } catch {
    return 1
  }
}

@objc public final class PhotoLibraryServiceStaticFuncs: NSObject {

  @objc(handlePhotoLibraryAction:)
  public static func handlePhotoLibraryAction(action: String) -> Int {
    if action == "clear" {
      let library = PHPhotoLibrary.shared()
      let options = PHFetchOptions()
      guard let client = FBPhotoLibraryClient.make(library: library, assets: PHAsset.fetchAssets(with: options)) else {
        return 1
      }
      return clearPhotoLibrary(client: client)
    } else {
      NSLog("Unknown action: %@", action)
      return 1
    }
  }

  @objc(clearWithClient:)
  public static func clear(client: Any) -> Int {
    guard let client = client as? FBPhotoLibraryClient else {
      return 1
    }
    return clearPhotoLibrary(client: client)
  }
}

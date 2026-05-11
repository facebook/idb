/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Swift-native async/await counterpart of `FBDeveloperDiskImageCommands`.
public protocol AsyncDeveloperDiskImageCommands: AnyObject {

  func mountedDiskImages() async throws -> [FBDeveloperDiskImage]

  func mountDiskImage(_ diskImage: FBDeveloperDiskImage) async throws -> FBDeveloperDiskImage

  func unmountDiskImage(_ diskImage: FBDeveloperDiskImage) async throws

  func mountableDiskImages() -> [FBDeveloperDiskImage]

  func ensureDeveloperDiskImageIsMounted() async throws -> FBDeveloperDiskImage
}

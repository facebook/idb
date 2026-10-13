/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public protocol DeveloperDiskImageCommands: AnyObject {

  func mountedDiskImages() async throws -> [DeveloperDiskImage]

  func mountDiskImage(_ diskImage: DeveloperDiskImage) async throws -> DeveloperDiskImage

  func unmountDiskImage(_ diskImage: DeveloperDiskImage) async throws

  func mountableDiskImages() -> [DeveloperDiskImage]

  func ensureMounted() async throws -> DeveloperDiskImage
}

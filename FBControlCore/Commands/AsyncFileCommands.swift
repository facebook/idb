/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Swift-native async/await counterpart of `FBFileCommands`.
/// Each method scopes the underlying file container to a closure body,
/// guaranteeing that the container's resources are torn down when the body returns.
public protocol AsyncFileCommands: AnyObject {

  func withFileCommandsForContainerApplication<R>(
    _ bundleID: String,
    body: (any FBFileContainerProtocol) async throws -> R
  ) async throws -> R

  func withFileCommandsForAuxillary<R>(
    body: (any FBFileContainerProtocol) async throws -> R
  ) async throws -> R

  func withFileCommandsForApplicationContainers<R>(
    body: (any FBFileContainerProtocol) async throws -> R
  ) async throws -> R

  func withFileCommandsForGroupContainers<R>(
    body: (any FBFileContainerProtocol) async throws -> R
  ) async throws -> R

  func withFileCommandsForRootFilesystem<R>(
    body: (any FBFileContainerProtocol) async throws -> R
  ) async throws -> R

  func withFileCommandsForMediaDirectory<R>(
    body: (any FBFileContainerProtocol) async throws -> R
  ) async throws -> R

  func withFileCommandsForProvisioningProfiles<R>(
    body: (any FBFileContainerProtocol) async throws -> R
  ) async throws -> R

  func withFileCommandsForMDMProfiles<R>(
    body: (any FBFileContainerProtocol) async throws -> R
  ) async throws -> R

  func withFileCommandsForSpringboardIconLayout<R>(
    body: (any FBFileContainerProtocol) async throws -> R
  ) async throws -> R

  func withFileCommandsForWallpaper<R>(
    body: (any FBFileContainerProtocol) async throws -> R
  ) async throws -> R

  func withFileCommandsForDiskImages<R>(
    body: (any FBFileContainerProtocol) async throws -> R
  ) async throws -> R

  func withFileCommandsForSymbols<R>(
    body: (any FBFileContainerProtocol) async throws -> R
  ) async throws -> R
}

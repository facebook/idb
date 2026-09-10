/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Each method scopes the underlying file container to a closure body,
/// guaranteeing that the container's resources are torn down when the body returns.
public protocol FileCommands {

  func withContainerApplication<R>(
    _ bundleID: String,
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R

  func withAuxiliary<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R

  func withApplicationContainers<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R

  func withGroupContainers<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R

  func withRootFilesystem<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R

  func withMediaDirectory<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R

  func withProvisioningProfiles<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R

  func withMDMProfiles<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R

  func withSpringboardIconLayout<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R

  func withWallpaper<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R

  func withDiskImages<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R

  func withSymbols<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R
}

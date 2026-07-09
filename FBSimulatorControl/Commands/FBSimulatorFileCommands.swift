/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@_implementationOnly import CoreSimulator
import FBControlCore
import Foundation

// swiftlint:disable force_cast force_unwrapping

public final class FBSimulatorFileCommands: NSObject, FBiOSTargetCommand {

  // MARK: - Properties

  private let simulator: FBSimulator

  // MARK: - Initializers

  public class func commands(with target: any FBiOSTarget) -> Self {
    unsafeDowncast(FBSimulatorFileCommands(simulator: target as! FBSimulator), to: self)
  }

  private init(simulator: FBSimulator) {
    self.simulator = simulator
    super.init()
  }

  // MARK: - FBFileCommands Implementation

  public func fileCommandsForContainerApplication(_ bundleID: String) -> FBFutureContext<FBContainedFile_ContainedRoot> {
    return
      (FBFuture<AnyObject>
      .onQueue(
        simulator.asyncQueue,
        resolve: { [weak self] in
          guard let self else {
            return FBFuture(error: FBControlCoreError.describe("FBSimulatorFileCommands deallocated").build())
          }
          return fbFutureFromAsync {
            let containedFile = try await self.containedFile(forApplication: bundleID)
            return FBFileContainer.fileContainer(forContainedFile: containedFile as AnyObject) as AnyObject
          }
        }
      )
      .onQueue(
        simulator.asyncQueue,
        contextualTeardown: { (_: Any, _: FBFutureState) -> FBFuture<NSNull> in
          FBFuture<NSNull>.empty()
        })) as! FBFutureContext<FBContainedFile_ContainedRoot>
  }

  public func fileCommandsForAuxillary() -> FBFutureContext<FBContainedFile_ContainedRoot> {
    return FBFutureContext<AnyObject>(result: FBFileContainer.fileContainer(forBasePath: simulator.auxillaryDirectory) as AnyObject) as! FBFutureContext<FBContainedFile_ContainedRoot>
  }

  public func fileCommandsForApplicationContainers() -> FBFutureContext<FBContainedFile_ContainedRoot> {
    return
      (FBFuture<AnyObject>
      .onQueue(
        simulator.workQueue,
        resolve: { [weak self] in
          guard let self else {
            return FBFuture(error: FBControlCoreError.describe("FBSimulatorFileCommands deallocated").build())
          }
          do {
            let containedFile = try self.containedFileForApplicationContainers()
            return FBFuture(result: FBFileContainer.fileContainer(forContainedFile: containedFile as AnyObject) as AnyObject)
          } catch {
            return FBFuture(error: error)
          }
        }
      )
      .onQueue(
        simulator.asyncQueue,
        contextualTeardown: { (_: Any, _: FBFutureState) -> FBFuture<NSNull> in
          FBFuture<NSNull>.empty()
        })) as! FBFutureContext<FBContainedFile_ContainedRoot>
  }

  public func fileCommandsForGroupContainers() -> FBFutureContext<FBContainedFile_ContainedRoot> {
    return
      (FBFuture<AnyObject>
      .onQueue(
        simulator.workQueue,
        resolve: { [weak self] in
          guard let self else {
            return FBFuture(error: FBControlCoreError.describe("FBSimulatorFileCommands deallocated").build())
          }
          do {
            let containedFile = try self.containedFileForGroupContainers()
            return FBFuture(result: FBFileContainer.fileContainer(forContainedFile: containedFile as AnyObject) as AnyObject)
          } catch {
            return FBFuture(error: error)
          }
        }
      )
      .onQueue(
        simulator.asyncQueue,
        contextualTeardown: { (_: Any, _: FBFutureState) -> FBFuture<NSNull> in
          FBFuture<NSNull>.empty()
        })) as! FBFutureContext<FBContainedFile_ContainedRoot>
  }

  public func fileCommandsForRootFilesystem() -> FBFutureContext<FBContainedFile_ContainedRoot> {
    let containedFile = containedFileForRootFilesystem()
    let fileContainer = FBFileContainer.fileContainer(forContainedFile: containedFile as AnyObject) as AnyObject
    return FBFutureContext<AnyObject>(result: fileContainer) as! FBFutureContext<FBContainedFile_ContainedRoot>
  }

  public func fileCommandsForMediaDirectory() -> FBFutureContext<FBContainedFile_ContainedRoot> {
    let mediaDirectory = (simulator.dataDirectory! as NSString).appendingPathComponent("Media")
    return FBFutureContext<AnyObject>(result: FBFileContainer.fileContainer(forBasePath: mediaDirectory) as AnyObject) as! FBFutureContext<FBContainedFile_ContainedRoot>
  }

  public func fileCommandsForMDMProfiles() -> FBFutureContext<FBContainedFile_ContainedRoot> {
    return
      FBControlCoreError
      .describe("fileCommandsForMDMProfiles not supported on simulators")
      .failFutureContext() as! FBFutureContext<FBContainedFile_ContainedRoot>
  }

  public func fileCommandsForProvisioningProfiles() -> FBFutureContext<FBContainedFile_ContainedRoot> {
    return
      FBControlCoreError
      .describe("fileCommandsForProvisioningProfiles not supported on simulators")
      .failFutureContext() as! FBFutureContext<FBContainedFile_ContainedRoot>
  }

  public func fileCommandsForSpringboardIconLayout() -> FBFutureContext<FBContainedFile_ContainedRoot> {
    return
      FBControlCoreError
      .describe("fileCommandsForSpringboardIconLayout not supported on simulators")
      .failFutureContext() as! FBFutureContext<FBContainedFile_ContainedRoot>
  }

  public func fileCommandsForWallpaper() -> FBFutureContext<FBContainedFile_ContainedRoot> {
    return
      FBControlCoreError
      .describe("fileCommandsForWallpaper not supported on simulators")
      .failFutureContext() as! FBFutureContext<FBContainedFile_ContainedRoot>
  }

  public func fileCommandsForDiskImages() -> FBFutureContext<FBContainedFile_ContainedRoot> {
    return
      FBControlCoreError
      .describe("fileCommandsForDiskImages not supported on simulators")
      .failFutureContext() as! FBFutureContext<FBContainedFile_ContainedRoot>
  }

  public func fileCommandsForSymbols() -> FBFutureContext<FBContainedFile_ContainedRoot> {
    return
      FBControlCoreError
      .describe("fileCommandsForSymbols not supported on simulators")
      .failFutureContext() as! FBFutureContext<FBContainedFile_ContainedRoot>
  }

  // MARK: - Contained file accessors

  private func containedFile(forApplication bundleID: String) async throws -> any FBContainedFile {
    let installedApplication = try await simulator.installedApplication(bundleID: bundleID)
    guard let container = installedApplication.dataContainer else {
      throw FBSimulatorError.describe("No data container present for application \(installedApplication)").build()
    }
    return FBFileContainer.containedFile(forBasePath: container) as! any FBContainedFile
  }

  private func containedFileForApplicationContainers() throws -> any FBContainedFile {
    let installedApps = try simulator.device.installedApps() as! [String: Any]
    var mapping: [String: String] = [:]
    for (bundleID, appInfo) in installedApps {
      guard let info = appInfo as? [String: Any],
        let dataContainer = info["DataContainer"] as? URL
      else {
        continue
      }
      mapping[bundleID] = dataContainer.path
    }
    return FBFileContainer.containedFile(forPathMapping: mapping) as! any FBContainedFile
  }

  private func containedFileForGroupContainers() throws -> any FBContainedFile {
    let installedApps = try simulator.device.installedApps() as! [String: Any]
    var bundleIDToURL: [String: URL] = [:]
    for (_, appInfo) in installedApps {
      guard let info = appInfo as? [String: Any],
        let appContainers = info["GroupContainers"] as? [String: URL]
      else {
        continue
      }
      for (key, value) in appContainers {
        bundleIDToURL[key] = value
      }
    }
    var pathMapping: [String: String] = [:]
    for (identifier, url) in bundleIDToURL {
      pathMapping[identifier] = url.path
    }
    return FBFileContainer.containedFile(forPathMapping: pathMapping) as! any FBContainedFile
  }

  private func containedFileForRootFilesystem() -> any FBContainedFile {
    FBFileContainer.containedFile(forBasePath: simulator.dataDirectory!) as! any FBContainedFile
  }
}

// MARK: - FBSimulator+FileCommands

extension FBSimulator: FileCommands {

  public func withFileCommandsForContainerApplication<R>(
    _ bundleID: String,
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await withFileContainer(fileCommands().fileCommandsForContainerApplication(bundleID), body: body)
  }

  public func withFileCommandsForAuxillary<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await withFileContainer(fileCommands().fileCommandsForAuxillary(), body: body)
  }

  public func withFileCommandsForApplicationContainers<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await withFileContainer(fileCommands().fileCommandsForApplicationContainers(), body: body)
  }

  public func withFileCommandsForGroupContainers<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await withFileContainer(fileCommands().fileCommandsForGroupContainers(), body: body)
  }

  public func withFileCommandsForRootFilesystem<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await withFileContainer(fileCommands().fileCommandsForRootFilesystem(), body: body)
  }

  public func withFileCommandsForMediaDirectory<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await withFileContainer(fileCommands().fileCommandsForMediaDirectory(), body: body)
  }

  public func withFileCommandsForProvisioningProfiles<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await withFileContainer(fileCommands().fileCommandsForProvisioningProfiles(), body: body)
  }

  public func withFileCommandsForMDMProfiles<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await withFileContainer(fileCommands().fileCommandsForMDMProfiles(), body: body)
  }

  public func withFileCommandsForSpringboardIconLayout<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await withFileContainer(fileCommands().fileCommandsForSpringboardIconLayout(), body: body)
  }

  public func withFileCommandsForWallpaper<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await withFileContainer(fileCommands().fileCommandsForWallpaper(), body: body)
  }

  public func withFileCommandsForDiskImages<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await withFileContainer(fileCommands().fileCommandsForDiskImages(), body: body)
  }

  public func withFileCommandsForSymbols<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await withFileContainer(fileCommands().fileCommandsForSymbols(), body: body)
  }

  /// Scopes the file container to `body`, exposing it through the
  /// `AsyncFileContainer` async API.
  private func withFileContainer<C: AsyncFileContainer, R>(
    _ context: FBFutureContext<C>,
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await withFBFutureContext(context) { container in
      try await body(container)
    }
  }
}

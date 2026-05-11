/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

@objc public protocol FBSimulatorFileCommandsProtocol: NSObjectProtocol {
  @objc(containedFileForApplication:error:)
  func containedFile(forApplication bundleID: String) throws -> any FBContainedFile

  @objc(containedFileForGroupContainersWithError:)
  func containedFileForGroupContainers() throws -> any FBContainedFile

  @objc(containedFileForApplicationContainersWithError:)
  func containedFileForApplicationContainers() throws -> any FBContainedFile

  func containedFileForRootFilesystem() -> any FBContainedFile
}

@objc(FBSimulatorFileCommands)
public final class FBSimulatorFileCommands: NSObject, FBSimulatorFileCommandsProtocol, FBiOSTargetCommand {

  // MARK: - Properties

  private let simulator: FBSimulator

  // MARK: - Initializers

  @objc(commandsWithTarget:)
  public class func commands(with target: any FBiOSTarget) -> Self {
    return unsafeDowncast(FBSimulatorFileCommands(simulator: target as! FBSimulator), to: self)
  }

  private init(simulator: FBSimulator) {
    self.simulator = simulator
    super.init()
  }

  // MARK: - FBFileCommands Implementation

  @objc
  public func fileCommandsForContainerApplication(_ bundleID: String) -> FBFutureContext<any FBFileContainerProtocol> {
    return
      (FBFuture<AnyObject>
      .onQueue(
        simulator.asyncQueue,
        resolve: { [weak self] in
          guard let self else {
            return FBFuture(error: FBControlCoreError.describe("FBSimulatorFileCommands deallocated").build())
          }
          do {
            let containedFile = try self.containedFile(forApplication: bundleID)
            return FBFuture(result: FBFileContainer.fileContainer(forContainedFile: containedFile as AnyObject) as AnyObject)
          } catch {
            return FBFuture(error: error)
          }
        }
      )
      .onQueue(
        simulator.asyncQueue,
        contextualTeardown: { (_: Any, _: FBFutureState) -> FBFuture<NSNull> in
          return FBFuture<NSNull>.empty()
        })) as! FBFutureContext<any FBFileContainerProtocol>
  }

  @objc
  public func fileCommandsForAuxillary() -> FBFutureContext<any FBFileContainerProtocol> {
    return FBFutureContext<AnyObject>(result: FBFileContainer.fileContainer(forBasePath: simulator.auxillaryDirectory) as AnyObject) as! FBFutureContext<any FBFileContainerProtocol>
  }

  @objc
  public func fileCommandsForApplicationContainers() -> FBFutureContext<any FBFileContainerProtocol> {
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
          return FBFuture<NSNull>.empty()
        })) as! FBFutureContext<any FBFileContainerProtocol>
  }

  @objc
  public func fileCommandsForGroupContainers() -> FBFutureContext<any FBFileContainerProtocol> {
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
          return FBFuture<NSNull>.empty()
        })) as! FBFutureContext<any FBFileContainerProtocol>
  }

  @objc
  public func fileCommandsForRootFilesystem() -> FBFutureContext<any FBFileContainerProtocol> {
    let containedFile = containedFileForRootFilesystem()
    let fileContainer = FBFileContainer.fileContainer(forContainedFile: containedFile as AnyObject) as AnyObject
    return FBFutureContext<AnyObject>(result: fileContainer) as! FBFutureContext<any FBFileContainerProtocol>
  }

  @objc
  public func fileCommandsForMediaDirectory() -> FBFutureContext<any FBFileContainerProtocol> {
    let mediaDirectory = (simulator.dataDirectory! as NSString).appendingPathComponent("Media")
    return FBFutureContext<AnyObject>(result: FBFileContainer.fileContainer(forBasePath: mediaDirectory) as AnyObject) as! FBFutureContext<any FBFileContainerProtocol>
  }

  @objc
  public func fileCommandsForMDMProfiles() -> FBFutureContext<any FBFileContainerProtocol> {
    return
      FBControlCoreError
      .describe("fileCommandsForMDMProfiles not supported on simulators")
      .failFutureContext() as! FBFutureContext<any FBFileContainerProtocol>
  }

  @objc
  public func fileCommandsForProvisioningProfiles() -> FBFutureContext<any FBFileContainerProtocol> {
    return
      FBControlCoreError
      .describe("fileCommandsForProvisioningProfiles not supported on simulators")
      .failFutureContext() as! FBFutureContext<any FBFileContainerProtocol>
  }

  @objc
  public func fileCommandsForSpringboardIconLayout() -> FBFutureContext<any FBFileContainerProtocol> {
    return
      FBControlCoreError
      .describe("fileCommandsForSpringboardIconLayout not supported on simulators")
      .failFutureContext() as! FBFutureContext<any FBFileContainerProtocol>
  }

  @objc
  public func fileCommandsForWallpaper() -> FBFutureContext<any FBFileContainerProtocol> {
    return
      FBControlCoreError
      .describe("fileCommandsForWallpaper not supported on simulators")
      .failFutureContext() as! FBFutureContext<any FBFileContainerProtocol>
  }

  @objc
  public func fileCommandsForDiskImages() -> FBFutureContext<any FBFileContainerProtocol> {
    return
      FBControlCoreError
      .describe("fileCommandsForDiskImages not supported on simulators")
      .failFutureContext() as! FBFutureContext<any FBFileContainerProtocol>
  }

  @objc
  public func fileCommandsForSymbols() -> FBFutureContext<any FBFileContainerProtocol> {
    return
      FBControlCoreError
      .describe("fileCommandsForSymbols not supported on simulators")
      .failFutureContext() as! FBFutureContext<any FBFileContainerProtocol>
  }

  // MARK: - FBSimulatorFileCommandsProtocol Implementation

  @objc
  public func containedFile(forApplication bundleID: String) throws -> any FBContainedFile {
    let installedApplication: FBInstalledApplication = try simulator.installedApplication(withBundleID: bundleID).await()
    guard let container = installedApplication.dataContainer else {
      throw FBSimulatorError.describe("No data container present for application \(installedApplication)").build()
    }
    return FBFileContainer.containedFile(forBasePath: container) as! any FBContainedFile
  }

  @objc
  public func containedFileForApplicationContainers() throws -> any FBContainedFile {
    let installedApps = try FBSimDeviceWrapper.installedApps(onDevice: simulator.device)
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

  @objc
  public func containedFileForGroupContainers() throws -> any FBContainedFile {
    let installedApps = try FBSimDeviceWrapper.installedApps(onDevice: simulator.device)
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

  @objc
  public func containedFileForRootFilesystem() -> any FBContainedFile {
    return FBFileContainer.containedFile(forBasePath: simulator.dataDirectory!) as! any FBContainedFile
  }
}

// MARK: - FBSimulator+AsyncFileCommands

extension FBSimulator: AsyncFileCommands {

  public func withFileCommandsForContainerApplication<R>(
    _ bundleID: String,
    body: (any FBFileContainerProtocol) async throws -> R
  ) async throws -> R {
    try await withFBFutureContext(fileCommands().fileCommandsForContainerApplication(bundleID), body: body)
  }

  public func withFileCommandsForAuxillary<R>(
    body: (any FBFileContainerProtocol) async throws -> R
  ) async throws -> R {
    try await withFBFutureContext(fileCommands().fileCommandsForAuxillary(), body: body)
  }

  public func withFileCommandsForApplicationContainers<R>(
    body: (any FBFileContainerProtocol) async throws -> R
  ) async throws -> R {
    try await withFBFutureContext(fileCommands().fileCommandsForApplicationContainers(), body: body)
  }

  public func withFileCommandsForGroupContainers<R>(
    body: (any FBFileContainerProtocol) async throws -> R
  ) async throws -> R {
    try await withFBFutureContext(fileCommands().fileCommandsForGroupContainers(), body: body)
  }

  public func withFileCommandsForRootFilesystem<R>(
    body: (any FBFileContainerProtocol) async throws -> R
  ) async throws -> R {
    try await withFBFutureContext(fileCommands().fileCommandsForRootFilesystem(), body: body)
  }

  public func withFileCommandsForMediaDirectory<R>(
    body: (any FBFileContainerProtocol) async throws -> R
  ) async throws -> R {
    try await withFBFutureContext(fileCommands().fileCommandsForMediaDirectory(), body: body)
  }

  public func withFileCommandsForProvisioningProfiles<R>(
    body: (any FBFileContainerProtocol) async throws -> R
  ) async throws -> R {
    try await withFBFutureContext(fileCommands().fileCommandsForProvisioningProfiles(), body: body)
  }

  public func withFileCommandsForMDMProfiles<R>(
    body: (any FBFileContainerProtocol) async throws -> R
  ) async throws -> R {
    try await withFBFutureContext(fileCommands().fileCommandsForMDMProfiles(), body: body)
  }

  public func withFileCommandsForSpringboardIconLayout<R>(
    body: (any FBFileContainerProtocol) async throws -> R
  ) async throws -> R {
    try await withFBFutureContext(fileCommands().fileCommandsForSpringboardIconLayout(), body: body)
  }

  public func withFileCommandsForWallpaper<R>(
    body: (any FBFileContainerProtocol) async throws -> R
  ) async throws -> R {
    try await withFBFutureContext(fileCommands().fileCommandsForWallpaper(), body: body)
  }

  public func withFileCommandsForDiskImages<R>(
    body: (any FBFileContainerProtocol) async throws -> R
  ) async throws -> R {
    try await withFBFutureContext(fileCommands().fileCommandsForDiskImages(), body: body)
  }

  public func withFileCommandsForSymbols<R>(
    body: (any FBFileContainerProtocol) async throws -> R
  ) async throws -> R {
    try await withFBFutureContext(fileCommands().fileCommandsForSymbols(), body: body)
  }
}

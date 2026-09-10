/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
import FBControlCore
import Foundation

public enum SimulatorFileError: Error {
  case noDataContainer(applicationDescription: String)
  case noDataDirectory(simulatorDescription: String)
  case unsupportedOnSimulators(operation: String)
}

extension SimulatorFileError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .noDataContainer(applicationDescription):
      return "No data container present for application \(applicationDescription)"
    case let .noDataDirectory(simulatorDescription):
      return "No data directory for \(simulatorDescription), it may not have been booted"
    case let .unsupportedOnSimulators(operation):
      return "\(operation) not supported on simulators"
    }
  }
}

public final class SimulatorFileCommands: FileCommands {

  private let simulator: FBSimulator

  // MARK: - Initializers

  public class func commands(with simulator: FBSimulator) -> SimulatorFileCommands {
    SimulatorFileCommands(simulator: simulator)
  }

  private init(simulator: FBSimulator) {
    self.simulator = simulator
  }

  // MARK: - Containers

  public func withFileCommandsForContainerApplication<R>(
    _ bundleID: String,
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await body(FBFileContainer.fileContainer(for: try await containedFile(forApplication: bundleID)))
  }

  public func withFileCommandsForAuxillary<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await body(FBFileContainer.fileContainer(forBasePath: simulator.auxillaryDirectory))
  }

  public func withFileCommandsForApplicationContainers<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await body(FBFileContainer.fileContainer(for: try containedFileForApplicationContainers()))
  }

  public func withFileCommandsForGroupContainers<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await body(FBFileContainer.fileContainer(for: try containedFileForGroupContainers()))
  }

  public func withFileCommandsForRootFilesystem<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await body(FBFileContainer.fileContainer(forBasePath: try requireDataDirectory()))
  }

  public func withFileCommandsForMediaDirectory<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    let mediaDirectory = (try requireDataDirectory() as NSString).appendingPathComponent("Media")
    return try await body(FBFileContainer.fileContainer(forBasePath: mediaDirectory))
  }

  public func withFileCommandsForProvisioningProfiles<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    throw SimulatorFileError.unsupportedOnSimulators(operation: #function)
  }

  public func withFileCommandsForMDMProfiles<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    throw SimulatorFileError.unsupportedOnSimulators(operation: #function)
  }

  public func withFileCommandsForSpringboardIconLayout<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    throw SimulatorFileError.unsupportedOnSimulators(operation: #function)
  }

  public func withFileCommandsForWallpaper<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    throw SimulatorFileError.unsupportedOnSimulators(operation: #function)
  }

  public func withFileCommandsForDiskImages<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    throw SimulatorFileError.unsupportedOnSimulators(operation: #function)
  }

  public func withFileCommandsForSymbols<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    throw SimulatorFileError.unsupportedOnSimulators(operation: #function)
  }

  // MARK: - Contained file accessors

  private func containedFile(forApplication bundleID: String) async throws -> any FBContainedFile {
    let installedApplication = try await simulator.installedApplication(bundleID: bundleID)
    guard let container = installedApplication.dataContainer else {
      throw SimulatorFileError.noDataContainer(applicationDescription: String(describing: installedApplication))
    }
    return FBFileContainer.containedFile(forBasePath: container)
  }

  private func containedFileForApplicationContainers() throws -> any FBContainedFile {
    var mapping: [String: String] = [:]
    for (bundleID, appInfo) in try simulator.device.installedApps() {
      guard let bundleID = bundleID as? String,
        let info = appInfo as? [String: Any],
        let dataContainer = info["DataContainer"] as? URL
      else {
        continue
      }
      mapping[bundleID] = dataContainer.path
    }
    return FBFileContainer.containedFile(forPathMapping: mapping)
  }

  private func containedFileForGroupContainers() throws -> any FBContainedFile {
    var bundleIDToURL: [String: URL] = [:]
    for appInfo in try simulator.device.installedApps().values {
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
    return FBFileContainer.containedFile(forPathMapping: pathMapping)
  }

  private func requireDataDirectory() throws -> String {
    guard let dataDirectory = simulator.dataDirectory else {
      throw SimulatorFileError.noDataDirectory(simulatorDescription: String(describing: simulator))
    }
    return dataDirectory
  }
}

// MARK: - FBSimulator+FileCommands

extension FBSimulator: FileCommands {

  public func withFileCommandsForContainerApplication<R>(
    _ bundleID: String,
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await file.withFileCommandsForContainerApplication(bundleID, body: body)
  }

  public func withFileCommandsForAuxillary<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await file.withFileCommandsForAuxillary(body: body)
  }

  public func withFileCommandsForApplicationContainers<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await file.withFileCommandsForApplicationContainers(body: body)
  }

  public func withFileCommandsForGroupContainers<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await file.withFileCommandsForGroupContainers(body: body)
  }

  public func withFileCommandsForRootFilesystem<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await file.withFileCommandsForRootFilesystem(body: body)
  }

  public func withFileCommandsForMediaDirectory<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await file.withFileCommandsForMediaDirectory(body: body)
  }

  public func withFileCommandsForProvisioningProfiles<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await file.withFileCommandsForProvisioningProfiles(body: body)
  }

  public func withFileCommandsForMDMProfiles<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await file.withFileCommandsForMDMProfiles(body: body)
  }

  public func withFileCommandsForSpringboardIconLayout<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await file.withFileCommandsForSpringboardIconLayout(body: body)
  }

  public func withFileCommandsForWallpaper<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await file.withFileCommandsForWallpaper(body: body)
  }

  public func withFileCommandsForDiskImages<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await file.withFileCommandsForDiskImages(body: body)
  }

  public func withFileCommandsForSymbols<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await file.withFileCommandsForSymbols(body: body)
  }
}
